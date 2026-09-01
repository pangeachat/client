import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_tap.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';

class RecordingSink implements CallAudioSink {
  final List<PcmChunk> delivered = [];
  final List<int> failIndices;
  int closes = 0;
  Completer<void>? block;

  /// How many times each chunk should fail before going through, so a test can
  /// tell a retry that recovered from one that never happened.
  final Map<int, int> failuresLeft;

  /// Every delivery attempt, including the ones that failed.
  final List<int> attempts = [];

  RecordingSink({this.failIndices = const [], Map<int, int>? failuresLeft})
    : failuresLeft = failuresLeft ?? {};

  @override
  Future<void> deliver(PcmChunk chunk, {Duration? within}) async {
    // Honoured, because the contract puts the limit on the attempt rather than
    // on whoever is waiting for it. A double that ignored it could not show a
    // hanging delivery being given up on at all.
    final blocked = block;
    if (blocked != null) {
      await (within == null ? blocked.future : blocked.future.timeout(within));
    }
    attempts.add(chunk.index);
    final left = failuresLeft[chunk.index] ?? 0;
    if (left > 0) {
      failuresLeft[chunk.index] = left - 1;
      throw StateError('sink temporarily refused chunk ${chunk.index}');
    }
    if (failIndices.contains(chunk.index)) {
      throw StateError('sink refused chunk ${chunk.index}');
    }
    delivered.add(chunk);
  }

  /// Chunks the recorder set aside instead of delivering, in the order it did.
  final List<PcmChunk> discardedChunks = [];

  @override
  void discarded(PcmChunk chunk) => discardedChunks.add(chunk);

  /// How many times closing should fail before it goes through.
  int closeFailures = 0;

  @override
  Future<bool> close() async {
    if (closeFailures > 0) {
      closeFailures--;
      throw StateError('the sink refused to close');
    }
    closes++;
    return drained;
  }

  /// What this fake reports about its drain. Defaults to a clean one so the
  /// existing tests, which are about closing rather than completeness, read
  /// unchanged.
  bool drained = true;
}

/// Stands in for a published track. [addAudioRenderer] is the only member the
/// recorder touches, and the real one is a plain callback registration.
class FakeTrack implements AudioTrack {
  AudioFrameCallback? onFrame;
  bool failNextRenderer = false;
  bool failCancel = false;
  AudioRendererOptions? options;
  int cancels = 0;

  @override
  CancelListenFunc addAudioRenderer({
    required AudioFrameCallback onFrame,
    AudioRendererOptions options = const AudioRendererOptions(),
  }) {
    if (failNextRenderer) {
      failNextRenderer = false;
      throw StateError('no renderer available');
    }
    this.onFrame = onFrame;
    this.options = options;
    return () async {
      cancels++;
      if (failCancel) throw StateError('the renderer will not detach');
      this.onFrame = null;
    };
  }

  void emit(int ms, {double amplitude = 0.3}) {
    final count = captureSampleRate * ms ~/ 1000;
    final samples = Int16List(count);
    final peak = (amplitude * 32767).round();
    for (var i = 0; i < count; i++) {
      samples[i] = i.isEven ? peak : -peak;
    }
    onFrame?.call(
      AudioFrame(
        sampleRate: captureSampleRate,
        channels: captureChannels,
        data: samples.buffer.asUint8List(),
        format: AudioFormat.Int16,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// [ms] of speech at [sampleRate], as the tap would hand it over.
Int16List speech(int ms, {int sampleRate = captureSampleRate}) {
  final samples = Int16List(sampleRate * ms ~/ 1000);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = i.isEven ? 9830 : -9830;
  }
  return samples;
}

/// Time a test can move, in the two ways the recorder reads it.
///
/// [ms] is the WALL clock, which the recorder reads exactly once per call.
/// [elapsed] is the monotonic counter it measures every gap from afterwards.
/// They move independently on purpose: a device clock correction moves one and
/// not the other, and that is the whole case these rules exist to survive. Nudge
/// [ms] alone and nothing about the recording may shift.
///
/// [pass] is what really happening looks like — time passing on both.
class Clock {
  int ms = 1700000000000;
  int elapsed = 0;

  int call() => ms;
  int monotonic() => elapsed;

  void pass(int by) {
    ms += by;
    elapsed += by;
  }
}

void main() {
  late RecordingSink sink;
  late FakeTrack track;
  late Clock clock;

  /// Every `runStartedAtMs` a chunker was built with, in the order the runs
  /// began. It is the one thing a test can see about where a run was placed.
  late List<int> runStarts;

  setUp(() {
    sink = RecordingSink();
    track = FakeTrack();
    clock = Clock();
    runStarts = [];
  });

  CallCaptureService service({
    RecordingSink? withSink,
    CallAudioTap? withTap,
    Duration? timeout,
    Duration? detach,
  }) => CallCaptureService(
    sink: withSink ?? sink,
    tap: withTap,
    deliveryTimeout: timeout ?? const Duration(seconds: 30),
    detachTimeout: detach ?? const Duration(seconds: 5),
    nowMs: clock.call,
    elapsedMs: clock.monotonic,
    newChunker: (firstIndex, sampleRate, channels, runStartedAtMs) {
      runStarts.add(runStartedAtMs);
      return PcmChunker(
        sampleRate: sampleRate,
        channels: channels,
        targetDuration: const Duration(milliseconds: 200),
        maxDuration: const Duration(milliseconds: 400),
        minSilence: const Duration(milliseconds: 100),
        firstIndex: firstIndex,
        runStartedAtMs: runStartedAtMs,
      );
    },
  );

  group('CallCaptureService', () {
    test(
      'requests the capture format rather than accepting the default',
      () async {
        await service().start(track);
        expect(track.options!.sampleRate, captureSampleRate);
        expect(track.options!.channels, captureChannels);
        expect(track.options!.format, AudioFormat.Int16);
      },
    );

    test('delivers chunks as the call runs, not only at the end', () async {
      final s = service();
      await s.start(track);
      for (var i = 0; i < 30; i++) {
        track.emit(20);
      }
      await pumpEventQueue();
      expect(
        sink.delivered,
        isNotEmpty,
        reason: '600ms exceeds the 400ms ceiling',
      );
      await s.stop();
    });

    test('a hangup stop does not wait for choreo, a handover stop does', () async {
      // The transcripts go to choreo. A call is over when the microphone and
      // the membership are released, never when a transcription answers --
      // and waiting for one held the account's ONE call open long after the
      // learner hung up. That refused the next call, and silently swallowed an
      // INCOMING ring, because a ring arriving while this account reads as busy
      // is dropped from the stream and never replayed.
      final s = service();
      await s.start(track);
      sink.block = Completer<void>();
      for (var i = 0; i < 30; i++) {
        track.emit(20);
      }
      await pumpEventQueue();

      var teardownDone = false;
      unawaited(
        s.stop(settleDeliveries: false).then((_) => teardownDone = true),
      );
      await pumpEventQueue();
      expect(
        teardownDone,
        isTrue,
        reason: 'a hangup may not wait on a delivery that is still running',
      );

      // The handover path still waits: it is about to START recording again,
      // and letting it run over a stretch still flushing is what the wait is
      // there to prevent.
      var handoverDone = false;
      unawaited(s.stop().then((_) => handoverDone = true));
      await pumpEventQueue();
      expect(
        handoverDone,
        isFalse,
        reason: 'a handover stop still settles what it handed over',
      );

      sink.block!.complete();
      await pumpEventQueue();
      expect(handoverDone, isTrue);
    });

    test('a tap that throws leaves nothing started', () async {
      // Recording it as started would refuse every later attempt with "already
      // running", costing the call its analytics for a failure that may have
      // been momentary.
      final failing = FakeTrack()..failNextRenderer = true;
      final s = service();

      await expectLater(s.start(failing), throwsStateError);
      expect(s.isRecording, isFalse);

      await s.start(track);
      expect(s.isRecording, isTrue, reason: 'and a retry works');
    });

    test('numbering continues when recording resumes in the same call', () async {
      // Another of the learner's devices can take over recording and hand it
      // back within one call. A second stretch numbered from zero would look
      // like a redelivery of the first and be discarded as already transcribed.
      final s = service();
      await s.start(track);
      for (var i = 0; i < 60; i++) {
        track.emit(20);
      }
      await s.stop();
      final firstRun = sink.delivered.map((c) => c.index).toList();
      expect(firstRun, isNotEmpty);

      await s.start(track);
      for (var i = 0; i < 60; i++) {
        track.emit(20);
      }
      await s.stop();

      final all = sink.delivered.map((c) => c.index).toList();
      expect(
        all,
        List.generate(all.length, (i) => i),
        reason: 'one unbroken run of indices across both stretches',
      );
      expect(all.length, greaterThan(firstRun.length));
    });

    test('a tap that will not detach is not stacked over', () async {
      // Starting again over an attached renderer would feed two taps into one
      // chunker and count the learner's own voice twice. Losing a stretch of
      // analytics is recoverable; counting it twice is not.
      final s = service();
      await s.start(track);
      track.failCancel = true;
      await s.stop();

      expect(
        s.start(track),
        throwsStateError,
        reason: 'refused rather than doubled',
      );
    });

    test('a second start while recording is refused', () async {
      final s = service();
      await s.start(track);
      await expectLater(s.start(track), throwsStateError);
    });

    test(
      'stop cancels the tap, flushes the tail, and closes the sink',
      () async {
        final s = service();
        await s.start(track);
        track.emit(100);
        await s.finish();

        expect(track.cancels, 1);
        expect(sink.delivered, hasLength(1), reason: 'the tail was flushed');
        expect(sink.closes, 1);
        expect(s.isRecording, isFalse);
      },
    );

    test('finishing twice does not double-flush or double-close', () async {
      final s = service();
      await s.start(track);
      track.emit(100);
      await s.stop();
      await s.finish();
      expect(sink.delivered, hasLength(1));
      expect(sink.closes, 1);
    });

    test('stop on a recorder that never started is a no-op', () async {
      await service().stop();
      expect(sink.closes, 0);
    });

    test('frames arriving after stop are ignored', () async {
      final s = service();
      await s.start(track);
      final captured = track.onFrame;
      await s.stop();
      final before = sink.delivered.length;

      // A renderer callback already in flight when the tap was cancelled.
      captured!(
        AudioFrame(
          sampleRate: captureSampleRate,
          channels: captureChannels,
          data: Int16List(captureSampleRate).buffer.asUint8List(),
          format: AudioFormat.Int16,
        ),
      );
      await pumpEventQueue();
      expect(sink.delivered, hasLength(before));
    });

    test('stop waits for chunks already handed to the sink', () async {
      final s = service();
      await s.start(track);
      sink.block = Completer<void>();
      for (var i = 0; i < 30; i++) {
        track.emit(20);
      }
      await pumpEventQueue();
      expect(sink.delivered, isEmpty, reason: 'delivery is held open');

      final stopped = s.stop();
      var done = false;
      unawaited(stopped.then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse, reason: 'stop must not abandon spoken audio');

      sink.block!.complete();
      await stopped;
      expect(sink.delivered, isNotEmpty);
    });

    test(
      'a chunk the sink refuses does not fail the call or the hangup',
      () async {
        final failing = RecordingSink(failIndices: [0]);
        final s = service(withSink: failing);
        await s.start(track);
        for (var i = 0; i < 60; i++) {
          track.emit(20);
        }
        await pumpEventQueue();
        await s.finish();

        expect(failing.closes, 1, reason: 'the call still ended cleanly');
        expect(
          failing.delivered.map((c) => c.index),
          isNot(contains(0)),
          reason: 'the refused chunk is lost, and only that chunk',
        );
        expect(failing.delivered, isNotEmpty);
      },
    );
  });

  group('CallCaptureService.pcmOf', () {
    AudioFrame frameOf(Uint8List data, AudioFormat format) => AudioFrame(
      sampleRate: captureSampleRate,
      channels: 1,
      data: data,
      format: format,
    );

    test('reads int16 samples little-endian', () async {
      final src = Int16List.fromList([0, 1, -1, 32767, -32768]);
      final out = CallCaptureService.pcmOf(
        frameOf(src.buffer.asUint8List(), AudioFormat.Int16),
      );
      expect(out, src);
    });

    test('reads a frame whose bytes sit at an odd offset', () async {
      final src = Int16List.fromList([5, -6, 7]);
      final padded = Uint8List(src.lengthInBytes + 1)
        ..setRange(1, src.lengthInBytes + 1, src.buffer.asUint8List());
      final window = Uint8List.sublistView(padded, 1);
      expect(
        window.offsetInBytes.isOdd,
        isTrue,
        reason: 'this is the case a zero-copy view cannot handle',
      );
      expect(CallCaptureService.pcmOf(frameOf(window, AudioFormat.Int16)), src);
    });

    test('converts float32 samples and clamps out-of-range values', () async {
      final src = Float32List.fromList([0.0, 1.0, -1.0, 0.5, 2.0, -2.0]);
      final out = CallCaptureService.pcmOf(
        frameOf(src.buffer.asUint8List(), AudioFormat.Float32),
      );
      expect(out, [0, 32767, -32767, 16384, 32767, -32767]);
    });
  });
  group('a chunk whose delivery fails', () {
    test('is retried rather than dropped', () async {
      // A chunk is up to ninety seconds of somebody's speech and there is no
      // second copy — the call is over by the time this fails. One request lost
      // on a weak connection used to lose all of it silently.
      final flaky = RecordingSink(failuresLeft: {0: 1});
      final s = service(withSink: flaky);
      await s.start(track);
      for (var i = 0; i < 30; i++) {
        track.emit(20);
      }
      await s.stop();

      expect(
        flaky.attempts.where((i) => i == 0).length,
        greaterThan(1),
        reason: 'the failed attempt must be tried again',
      );
      expect(
        flaky.delivered.map((c) => c.index),
        contains(0),
        reason: 'and the words must arrive',
      );
    });

    test('is given up on quietly once the attempts run out', () async {
      // A chunk that will never send must not hold a hangup open forever, and
      // must not take the call down with it.
      final dead = RecordingSink(failIndices: const [0]);
      final s = service(withSink: dead);
      await s.start(track);
      for (var i = 0; i < 30; i++) {
        track.emit(20);
      }

      await expectLater(s.stop(), completes);
      expect(
        dead.attempts.where((i) => i == 0).length,
        3,
        reason: 'bounded attempts, not an unbounded loop',
      );
    });
  });
  group('a device with no tap', () {
    test('records nothing and leaves the call alone', () async {
      // Some devices have no point to read from that sits after echo
      // cancellation. Recording nothing costs the analytics; recording from the
      // wrong point would credit the other person's words to this learner.
      final s = service(withTap: _NoTap());
      await s.start(track);
      for (var i = 0; i < 30; i++) {
        track.emit(20);
      }
      await s.stop();

      expect(s.isRecording, isFalse);
      expect(sink.delivered, isEmpty);
    });
  });

  group('frames a tap hands over WHILE it detaches', () {
    test(
      'are dropped — the microphone is off the record once a stop begins',
      () async {
        // This once kept them: the tap's tail is the end of a sentence, and it
        // arrives during the detach. But a detach can stall for its bounded
        // seconds, and everything delivered in that window after a hangup is
        // post-hangup microphone audio — the learner's private conversation once
        // they believed the call was over. There is no marker on a frame that
        // tells the tail from that, so the safer of the two wins: nothing is
        // recorded once the stop has begun. The cost is at most the tap's last
        // un-flushed batch; everything up to the hangup is already in the chunker.
        final tap = _TailOnDetachTap();
        final s = service(withTap: tap);
        await s.start(track);
        await s.stop();

        expect(
          sink.delivered.expand((c) => c.pcm),
          isEmpty,
          reason: 'audio handed over during a detach must not be recorded',
        );
      },
    );
  });

  group('a stop landing while the tap is still attaching', () {
    test('leaves no tap attached behind it', () async {
      final tap = _SlowToAttachTap();
      final s = service(withTap: tap);

      final starting = s.start(track);
      await pumpEventQueue();
      await s.stop();
      tap.finishAttaching();
      await starting;

      expect(
        tap.detached,
        isTrue,
        reason: 'a tap that arrived after the stop must be released',
      );
      expect(s.isRecording, isFalse);
    });
  });

  group('a delivery that hangs', () {
    test(
      'does not hold the end of the call open',
      () async {
        // A request that fails says so; one that hangs says nothing, and the
        // hangup waits for every chunk still in flight.
        final stuck = RecordingSink()..block = Completer<void>();
        final s = service(
          withSink: stuck,
          timeout: const Duration(milliseconds: 20),
        );
        await s.start(track);
        for (var i = 0; i < 30; i++) {
          track.emit(20);
        }

        await expectLater(
          s.finish().timeout(const Duration(seconds: 5)),
          completes,
        );
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });

  group('a muted recorder', () {
    test('drops frames so muted speech is never recorded', () async {
      // LiveKit's mute only stops publishing to the peer; on Android the tap
      // reads the capture module directly, upstream of that, so the recorder
      // needs its own gate or a muted learner is still transcribed.
      final s = service();
      await s.start(track);
      s.setMuted(true);
      for (var i = 0; i < 60; i++) {
        track.emit(20);
      }
      await s.stop();
      expect(sink.delivered, isEmpty, reason: 'muted speech must not record');
    });

    test('resumes capturing once unmuted', () async {
      final s = service();
      await s.start(track);
      s.setMuted(true);
      for (var i = 0; i < 20; i++) {
        track.emit(20);
      }
      s.setMuted(false);
      for (var i = 0; i < 60; i++) {
        track.emit(20);
      }
      await s.stop();
      expect(sink.delivered, isNotEmpty, reason: 'speech after unmute records');
    });
  });

  group('a hangup that catches the tap mid-detach', () {
    test('drops frames that arrive after the stop has begun', () async {
      // Detaching is a platform round-trip that can take its bounded seconds.
      // Frames arriving in that window, after the learner hung up, are
      // post-hangup microphone audio and must not be recorded.
      final tap = _SlowDetachTap();
      final s = service(withTap: tap);
      await s.start(track);

      int total() =>
          sink.delivered.fold(0, (n, c) => n + c.pcm.lengthInBytes ~/ 2);

      // Half a second of speech BEFORE the hangup.
      final speech = Int16List(12000)..fillRange(0, 12000, 8000);
      tap.onFrames!(speech, 24000, 1);
      await pumpEventQueue();

      // Hang up: stop begins and the detach hangs.
      final stopping = s.stop();
      await pumpEventQueue();

      // A full second of speech arrives WHILE the detach is stuck.
      tap.onFrames!(speech, 24000, 1);
      tap.onFrames!(speech, 24000, 1);
      await pumpEventQueue();

      tap.finishDetach();
      await stopping;

      // Only the pre-hangup half second was recorded; the rest was dropped.
      expect(
        total(),
        lessThan(20000),
        reason: 'post-hangup microphone audio must not be recorded',
      );
    });
  });

  group('a close that fails', () {
    test('is tried again rather than remembered as done', () async {
      // Marking the call finished before the close had succeeded meant the one
      // retry that could have fixed it skipped the work — the same mistake as
      // clearing a handle before the operation it stands for has succeeded.
      sink.closeFailures = 1;
      final s = service();
      await s.start(track);

      await expectLater(s.finish(), throwsStateError);
      expect(sink.closes, 0);

      await s.finish();
      expect(sink.closes, 1, reason: 'the retry must actually close it');
    });
  });

  group('two stops arriving together', () {
    test('close the sink once, not twice', () async {
      // A hangup and a disconnect routinely land together. A guard followed by
      // an await lets both past, and the sink is then closed twice.
      final s = service(withTap: _SlowTap());
      await s.start(track);
      for (var i = 0; i < 30; i++) {
        track.emit(20);
      }

      await Future.wait([s.finish(), s.finish()]);

      expect(sink.closes, 1);
    });
  });

  group('a tap whose detach never comes back', () {
    test('does not hold the hangup open for ever', () async {
      final capture = service(
        withTap: _SilentDetachTap(),
        detach: const Duration(milliseconds: 50),
      );
      await capture.start(track);

      // Teardown waits on this. Unbounded, the hangup never finished: the call
      // was never written and every word of it went uncredited, to protect a
      // tap that was lost either way.
      await capture.stop().timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('stop must not wait on a tap that is gone'),
      );

      // Kept, like any tap that would not come off, so the next stop tries it
      // again and no new recording starts over the top of it.
      await expectLater(capture.start(track), throwsStateError);
    });
  });

  group('the end of a call', () {
    test('waits for a delivery that stopping gave up waiting on', () async {
      // Stopping bounds its wait so a stuck upload cannot hold up a handover
      // mid-call. The end of a call has nothing to hold up, and closing before
      // a slow delivery lands would credit the learner from a transcript
      // missing the words they were still waiting on.
      final gate = Completer<void>();
      final slow = RecordingSink()..block = gate;
      final capture = service(withSink: slow);
      await capture.start(track);
      for (var i = 0; i < 30; i++) {
        track.emit(20);
      }
      await pumpEventQueue();

      var finished = false;
      final finishing = capture.finish().then((_) => finished = true);
      await pumpEventQueue();
      expect(
        finished,
        isFalse,
        reason: 'the call is not finished while its audio is still going',
      );

      gate.complete();
      await finishing;
      expect(slow.closes, 1);
    });
  });

  group('a detach that throws before it returns', () {
    test('is still retained, not lost', () async {
      // A DetachTap may run synchronously, and so may its failure. Called
      // outside the guard, that throw escaped the release path altogether and
      // nothing ever came back to the tap — which stayed attached, silently.
      final capture = service(withTap: _ThrowsOnDetachTap());
      await capture.start(track);
      await capture.stop();

      await expectLater(
        capture.start(track),
        throwsStateError,
        reason: 'a tap still attached must refuse a second recording',
      );
    });
  });

  group('a detach that is still running', () {
    test('is waited for, not started a second time', () async {
      // Giving up waiting does not stop it. Asking the same tap again runs a
      // second stop over the top of the first — on Android that is the platform
      // capture being torn down twice — and the tap can end up held for good,
      // which stops this device recording anything ever again.
      final tap = _SilentDetachTap();
      final capture = service(
        withTap: tap,
        detach: const Duration(milliseconds: 50),
      );
      await capture.start(track);
      await capture.stop();
      expect(tap.detachCalls, 1);

      // The next stop comes back to it and finds it still going.
      await capture.stop();
      expect(
        tap.detachCalls,
        1,
        reason: 'a detach already in flight is waited for, never re-asked',
      );

      // Once it finally answers, the tap is free and recording can start again.
      tap.finish.complete();
      await capture.stop();
      await capture.start(track);
    });

    test(
      'frees itself the moment it answers, without waiting for a stop',
      () async {
        // Only a stop ever comes back to a held tap, and a stop happens at the
        // END of a call. A tap that timed out and then detached a second later
        // would block every recorder election until then, and this device would
        // sit silent through the whole conversation.
        final tap = _SilentDetachTap();
        final capture = service(
          withTap: tap,
          detach: const Duration(milliseconds: 50),
        );
        await capture.start(track);
        await capture.stop();
        await expectLater(capture.start(track), throwsStateError);

        // The platform finally answers, mid-call, with nothing else happening.
        tap.finish.complete();
        await pumpEventQueue();

        await capture.start(track);
        expect(capture.isRecording, isTrue);
      },
    );
  });

  group('where a run sits', () {
    test('a mute cuts the run, and the next one starts after the gap', () async {
      // The flush has to happen in setMuted, not in _onFrames: after a mute no
      // more frames arrive, so a flush waiting for one never runs and the words
      // before the mute sit in the chunker until the next stop — coming out
      // glued to whatever was said after the learner unmuted.
      final s = service();
      await s.start(track);
      for (var i = 0; i < 15; i++) {
        track.emit(20); // 300ms, under the 400ms ceiling
      }
      await pumpEventQueue();
      expect(sink.delivered, isEmpty, reason: 'nothing has been cut yet');

      s.setMuted(true);
      await pumpEventQueue();
      expect(sink.delivered.map((c) => c.index), [
        0,
      ], reason: 'the mute flushed the tail');

      clock.pass(5000);
      s.setMuted(false);
      for (var i = 0; i < 15; i++) {
        track.emit(20);
      }
      await s.stop();
      await pumpEventQueue();

      expect(
        sink.delivered.map((c) => c.index),
        [0, 1],
        reason:
            'the run after the mute numbers on from the tail, never over it',
      );
      expect(
        sink.delivered[1].startedAtMs - sink.delivered[0].startedAtMs,
        5000,
        reason: 'a mute is an absence of capture, so it is a gap in the record',
      );
    });

    test('a sample-rate change is not a gap; a mute is', () async {
      // A rate change happens inside ONE callback and the very same batch
      // continues into the new chunker, so there is no silence between them —
      // only a boundary we imposed. Reading the clock there invents a gap and
      // pushes the first new-rate chunk later than the speech actually was.
      final tap = _DrivableTap();
      final s = service(withTap: tap);
      await s.start(track);

      tap.onFrames!(speech(100), captureSampleRate, 1);
      clock.pass(1000); // a clock read below would invent a whole second
      tap.onFrames!(speech(100, sampleRate: 24000), 24000, 1);
      await pumpEventQueue();

      expect(sink.delivered.map((c) => c.index), [0]);
      expect(sink.delivered.single.startedAtMs, runStarts[0]);
      expect(
        runStarts[1],
        runStarts[0] + 100,
        reason: 'the new rate continues exactly where the old one ended',
      );

      clock.pass(5000);
      s.setMuted(true);
      s.setMuted(false);
      tap.onFrames!(speech(100, sampleRate: 24000), 24000, 1);
      await pumpEventQueue();

      expect(
        runStarts[2],
        clock.ms - 100,
        reason: 'a mute IS an absence of capture, so its run takes the gap',
      );
    });

    test('a channel-count change ends the run, like a rate change', () async {
      // Samples already collected cannot be reinterpreted in a format they were
      // not captured in: re-reading mono audio as stereo halves its frame count
      // and stretches it, exactly as re-reading its rate would. And like a rate
      // change it is a boundary WE imposed inside one batch, not an absence of
      // capture, so it must not open a gap.
      final tap = _DrivableTap();
      final s = service(withTap: tap);
      await s.start(track);

      tap.onFrames!(speech(100), captureSampleRate, 1);
      clock.pass(1000); // a clock read below would invent a whole second
      tap.onFrames!(speech(100), captureSampleRate, 2);
      await pumpEventQueue();

      expect(
        sink.delivered.map((c) => c.index),
        [0],
        reason: 'the mono run was cut when the format changed under it',
      );
      expect(sink.delivered.single.channels, 1);
      expect(
        runStarts[1],
        runStarts[0] + 100,
        reason: 'a format change is not a gap, whichever half of it changed',
      );
    });

    test('a stereo frame is measured as stereo, not as what we asked for', () {
      // The batch duration positions the run, and it divides interleaved
      // samples by the channel count. Dividing by the count we REQUESTED puts
      // it out by exactly that factor.
      final tap = _DrivableTap();
      final s = service(withTap: tap);

      return s.start(track).then((_) async {
        // 100ms of STEREO is twice the samples of 100ms of mono.
        tap.onFrames!(
          speech(100, sampleRate: captureSampleRate * 2),
          captureSampleRate,
          2,
        );
        await pumpEventQueue();

        expect(
          runStarts.single,
          clock.ms - 100,
          reason: 'one hundred milliseconds of audio, not two hundred',
        );
      });
    });

    test('a stereo run is chunked and labelled as stereo', () async {
      // The chunker's whole frame accounting divides bytes by the channel
      // count, and that count goes into the WAV header choreo reads. Built with
      // the count we REQUESTED, the same bytes measure twice as long, cut in
      // the wrong places, and are handed to the provider labelled as something
      // they are not.
      final tap = _DrivableTap();
      final s = service(withTap: tap);
      await s.start(track);

      // 300ms of STEREO: under the 400ms ceiling as stereo, over it as mono.
      tap.onFrames!(
        speech(300, sampleRate: captureSampleRate * 2),
        captureSampleRate,
        2,
      );
      await s.stop();
      await pumpEventQueue();

      final chunk = sink.delivered.single;
      expect(
        chunk.channels,
        2,
        reason: 'the header must say what the bytes are',
      );
      expect(
        chunk.duration.inMilliseconds,
        300,
        reason: 'labelled mono, the same bytes would measure 600ms',
      );
    });

    test('the DEFAULT chunker is built from the format that arrived', () async {
      // Every other test here injects a fake chunker factory, so the one
      // production actually uses had the requested channel count baked into it
      // with nothing exercising the difference.
      final tap = _DrivableTap();
      final s = CallCaptureService(
        sink: sink,
        tap: tap,
        nowMs: clock.call,
        elapsedMs: clock.monotonic,
      );
      await s.start(track);

      tap.onFrames!(
        speech(300, sampleRate: captureSampleRate * 2),
        captureSampleRate,
        2,
      );
      await s.stop();
      await pumpEventQueue();

      final chunk = sink.delivered.single;
      expect(chunk.channels, 2);
      expect(
        chunk.duration.inMilliseconds,
        300,
        reason: 'labelled mono, the same bytes would measure 600ms',
      );
    });

    test('a clock corrected mid-call moves nothing, either way', () async {
      // This test used to assert only that a BACKWARD step could not move a run
      // earlier, and that the floor on the previous run's end was what stopped
      // it. That pinned half a rule. A clock nudged FORWARD between runs
      // stamped the next one arbitrarily late and sailed through the render
      // gate, because a position invented an hour into the future is still
      // non-null and still non-decreasing.
      //
      // Bounding one direction and leaving the other open was the tell that the
      // mechanism was wrong rather than the bound. A wall clock is not for
      // measuring an elapsed interval: it is read once, and every gap after
      // that is measured monotonically. So what is pinned now is that a
      // correction in EITHER direction changes nothing at all.
      final s = service();
      await s.start(track);
      for (var i = 0; i < 10; i++) {
        track.emit(20); // 200ms
      }
      await s.stop();
      await pumpEventQueue();

      // Five real seconds, and the device clock jumps a minute forward.
      clock.pass(5000);
      clock.ms += 60000;
      await s.start(track);
      for (var i = 0; i < 10; i++) {
        track.emit(20);
      }
      await s.stop();
      await pumpEventQueue();

      // Five more real seconds, and it is corrected two minutes backward.
      clock.pass(5000);
      clock.ms -= 120000;
      await s.start(track);
      for (var i = 0; i < 10; i++) {
        track.emit(20);
      }
      await s.stop();
      await pumpEventQueue();

      expect(sink.delivered, hasLength(3));
      expect(
        sink.delivered[1].startedAtMs - sink.delivered[0].startedAtMs,
        5000,
        reason: 'five seconds of speech apart, not sixty-five',
      );
      expect(
        sink.delivered[2].startedAtMs - sink.delivered[1].startedAtMs,
        5000,
        reason: 'and the correction back the other way moves it no further',
      );
    });

    test('a monotonic counter that stalls cannot reorder two runs', () async {
      // The floor stays, as defence rather than as the mechanism. Some
      // platforms hold a monotonic counter still while the device sleeps, and a
      // run measured from a stalled one would land before the run before it had
      // finished. Compressed and in ORDER is a failure this design already
      // accepts. Out of order is not.
      final s = service();
      await s.start(track);
      for (var i = 0; i < 10; i++) {
        track.emit(20); // 200ms
      }
      await s.stop();
      await pumpEventQueue();

      // Nothing moves at all, on either clock.
      await s.start(track);
      for (var i = 0; i < 10; i++) {
        track.emit(20);
      }
      await s.stop();
      await pumpEventQueue();

      expect(sink.delivered, hasLength(2));
      expect(
        sink.delivered[1].startedAtMs,
        sink.delivered[0].startedAtMs + 200,
        reason:
            'the later run begins where the earlier one ended, never before',
      );
    });
  });

  group('a run that ends without a stop', () {
    test('delivers the audio a failed open had already handed over', () async {
      // If the tap called us back, the platform was already handing over
      // microphone samples and only the handshake failed. Leaving that audio in
      // place let the next run inherit it, glued across the gap between them.
      final tap = _FramesThenFailsTap();
      final s = service(withTap: tap);
      final starting = s.start(track);
      await pumpEventQueue();

      tap.finishOpening();
      await expectLater(starting, throwsStateError);
      await pumpEventQueue();

      expect(sink.delivered.map((c) => c.index), [0]);
      expect(sink.delivered.single.pcm.lengthInBytes ~/ 2, 1600);
    });

    test('does not cut the run that replaced it', () async {
      // A stop that lands first ends the run first, and a start after it owns
      // whatever chunker exists now. An open failing at that point must be a
      // no-op, not a second cut through somebody else's sentence.
      final tap = _FramesThenFailsTap();
      final s = service(withTap: tap);
      final starting = s.start(track);
      await pumpEventQueue();
      await s.stop();
      expect(sink.delivered.map((c) => c.index), [0]);

      await s.start(track); // opens cleanly, and hands over its own 100ms
      tap.onFrames!(speech(100), captureSampleRate, 1);
      tap.finishOpening();
      await expectLater(starting, throwsStateError);
      await pumpEventQueue();
      tap.onFrames!(speech(50), captureSampleRate, 1);
      await s.stop();
      await pumpEventQueue();

      expect(sink.delivered.map((c) => c.index), [0, 1]);
      expect(
        sink.delivered[1].pcm.lengthInBytes ~/ 2,
        captureSampleRate * 250 ~/ 1000,
        reason: 'the second run is one stretch, not two split by a stale open',
      );
    });

    test('drops frames from a tap that outlived it', () async {
      // When `tap.open` throws there is no detach handle, so a tap installed
      // before the throw cannot be tracked and never comes off. _onFrames was
      // gated only by the global `_running`, which the NEXT start sets before
      // its own open — so the leaked tap's frames were accepted straight into
      // the run that followed.
      final tap = _LeakingTap();
      final s = service(withTap: tap);
      await expectLater(s.start(track), throwsStateError);
      final leaked = tap.onFrames!;

      await s.start(track);
      leaked(speech(100), captureSampleRate, 1);
      await s.stop();
      await pumpEventQueue();

      expect(
        sink.delivered,
        isEmpty,
        reason: 'a callback may only ever feed the run it was opened for',
      );
    });
  });

  group('a start that overtakes a stop', () {
    test('does not inherit the previous run\'s audio', () async {
      // _stop clears `_running` early but does not take the chunker until AFTER
      // awaiting the detach. A start landing inside that window passed every
      // guard, attached a second tap, and fed the OLD chunker — so one chunk
      // held both runs, with the gap between them written out of the record.
      final tap = _SlowDetachTap();
      final s = service(withTap: tap);
      await s.start(track);
      tap.onFrames!(speech(100), captureSampleRate, 1);
      await pumpEventQueue();

      final stopping = s.stop();
      await pumpEventQueue();

      final starting = s.start(track);
      await pumpEventQueue();

      // Speech arriving while the stop is still unwinding. It belongs to
      // nothing: the run it was captured for is over, and the run that follows
      // has not been opened.
      tap.onFrames!(speech(100), captureSampleRate, 1);
      await pumpEventQueue();

      tap.finishDetach();
      await stopping;
      await starting;

      tap.onFrames!(speech(100), captureSampleRate, 1);
      await s.stop();
      await pumpEventQueue();

      expect(sink.delivered.map((c) => c.index), [0, 1]);
      expect(
        sink.delivered.map((c) => c.pcm.lengthInBytes ~/ 2),
        [1600, 1600],
        reason: 'two runs of 100ms each, never one chunk holding both',
      );
    });
  });

  group('a tap that will not let go', () {
    test('is kept rather than dropped when it arrives too late', () async {
      final tap = _StubbornSlowTap();
      final capture = service(withTap: tap);
      final starting = capture.start(track);
      // The call ends while the tap is still attaching, so what arrives belongs
      // to a recording that is already over.
      await capture.stop();
      tap.finishAttaching();
      await starting;

      expect(tap.detachAttempts, 1, reason: 'it was asked, and refused');
      expect(tap.detached, isFalse);

      // The next start comes back to it BEFORE deciding anything. A stop is the
      // only other thing that ever returns to a held tap, and a device that
      // keeps winning the election never performs one -- so leaving the retry
      // to the stop kept this device silent for the whole call over one detach
      // that would have succeeded on the second ask.
      await capture.start(track);
      expect(tap.detached, isTrue, reason: 'the retry let the old tap go');
      expect(
        capture.isRecording,
        isTrue,
        reason: 'and the stretch it was refusing actually happened',
      );
      expect(capture.canCapture, isTrue);
      await capture.stop();
    });

    test('does not attach after a stop that landed inside the retry', () async {
      // The retry is the ONE yield between the wait for an in-flight stop at
      // the top of start() and the moment a tap is attached, so it reopens by
      // hand the exact window that wait exists to close. A stop that lands and
      // finishes inside it is invisible -- and if it was the last stop of the
      // call, the tap this start went on to attach would never come off, and
      // the microphone would stay open on a conversation that had ended.
      final tap = _FreesOnRetryTap();
      final capture = service(withTap: tap);
      await capture.start(track);
      await capture.stop();
      expect(tap.detachAttempts, 2, reason: 'the stop asked twice and lost');

      final starting = capture.start(track);
      await pumpEventQueue();
      // The hangup, landing while the retry is still deciding.
      await capture.stop();
      tap.finishDetach();

      await expectLater(starting, throwsStateError);
      expect(
        tap.opens,
        1,
        reason: 'no tap was attached after the last stop of the call',
      );
      expect(capture.isRecording, isFalse);
    });

    test('still refuses when the retry cannot free it either', () async {
      // The other half of the same line. A tap that will not come off however
      // often it is asked is not a bad moment, and a second tap laid over it
      // would feed one chunker from two sources and count the learner twice.
      final tap = _ThrowsOnDetachTap();
      final capture = service(withTap: tap);
      await capture.start(track);
      await capture.stop();

      await expectLater(capture.start(track), throwsStateError);
      expect(
        capture.canCapture,
        isFalse,
        reason: 'a device holding a tap it cannot release cannot record',
      );
    });
  });

  group('whether audio is actually reaching the recorder', () {
    test(
      'an attached tap that has delivered nothing is not capturing',
      () async {
        // The distinction the whole discard rests on. A tap that attached and
        // then produced no frame -- the failure the first-frame watchdog exists
        // to catch -- answers TRUE to isRecording for the fifteen seconds the
        // watchdog takes to fire. A sibling told THAT would throw away the only
        // copy of what the learner said.
        final capture = service();
        await capture.start(track);

        expect(capture.isRecording, isTrue);
        expect(capture.capturingAudio, isFalse);
      },
    );

    test('a run is named only once audio has actually arrived', () async {
      // The token a sibling is allowed to destroy its own audio on. An attached
      // tap that has produced nothing names no run at all.
      final capture = service();
      await capture.start(track);
      expect(capture.captureRun, isNull);

      track.emit(20);

      expect(capture.captureRun, isNotNull);
      await capture.stop();
    });

    test('a stop and a restart are DIFFERENT runs', () async {
      // The whole reason it is a token. Attribute writes are last-write-wins,
      // so a sibling watching this across the SFU can read the same value
      // before and after a stop-restart pair and never learn the gap happened.
      // The audio in that gap belongs to nobody.
      final capture = service();
      await capture.start(track);
      track.emit(20);
      final first = capture.captureRun;
      await capture.stop();

      await capture.start(track);
      track.emit(20);

      expect(capture.captureRun, isNotNull);
      expect(capture.captureRun, isNot(first));
      await capture.stop();
    });

    test('a mute and an unmute are different runs too', () async {
      // A mute IS a gap in what this device holds, so it has to move the token
      // exactly as a stop does.
      final capture = service();
      await capture.start(track);
      track.emit(20);
      final first = capture.captureRun;

      capture.setMuted(true);
      expect(capture.captureRun, isNull);
      capture.setMuted(false);
      track.emit(20);

      expect(capture.captureRun, isNot(first));
      await capture.stop();
    });

    test('a sample-rate change is the SAME run', () async {
      // It swaps the chunker inside one callback with no silence between, so
      // the audio is continuous. Moving the token here would tell a sibling
      // about a gap that did not happen and cost a duplicate.
      final capture = service();
      await capture.start(track);
      track.emit(20);
      final first = capture.captureRun;

      track.onFrame!(
        AudioFrame(
          sampleRate: 16000,
          channels: captureChannels,
          data: Int16List(320).buffer.asUint8List(),
          format: AudioFormat.Int16,
        ),
      );

      expect(capture.captureRun, first);
      await capture.stop();
    });

    test('a frame that arrives makes it true, and says so at once', () async {
      // Announced promptly rather than at the next election, because the window
      // it shortens is the one in which a sibling displacing this device cannot
      // yet tell it from a device whose tap died.
      var started = 0;
      final capture = service();
      capture.onCaptureStarted = () => started++;
      await capture.start(track);
      expect(started, 0);

      track.emit(20);

      expect(capture.capturingAudio, isTrue);
      expect(started, 1);
      await capture.stop();
    });

    test('the news is once per run, not once per format change', () async {
      // A sample-rate change ends the run and opens a new chunker inside one
      // callback, with no yield between, so nothing outside ever saw it stop.
      // Reporting a fresh start there would tell the siblings something that
      // did not happen.
      var started = 0;
      final capture = service();
      capture.onCaptureStarted = () => started++;
      await capture.start(track);
      track.emit(20);
      // The same run, at a different rate. It ends the chunker and opens
      // another inside this one callback.
      track.onFrame!(
        AudioFrame(
          sampleRate: 16000,
          channels: captureChannels,
          data: Int16List(320).buffer.asUint8List(),
          format: AudioFormat.Int16,
        ),
      );

      expect(started, 1);
      expect(capture.capturingAudio, isTrue);
      await capture.stop();
    });

    test('a stop takes it back', () async {
      final capture = service();
      await capture.start(track);
      track.emit(20);
      expect(capture.capturingAudio, isTrue);

      await capture.stop();

      expect(capture.capturingAudio, isFalse);
    });

    test('a mute takes it back too', () async {
      // A mute ends the run and lets the chunker go, because a gap in the
      // transcript is what a mute should be -- so a muted device is not holding
      // anybody's words, and must not tell a sibling that it is.
      final capture = service();
      await capture.start(track);
      track.emit(20);
      expect(capture.capturingAudio, isTrue);

      capture.setMuted(true);

      expect(capture.isRecording, isTrue, reason: 'the tap is still attached');
      expect(capture.capturingAudio, isFalse);
      await capture.stop();
    });
  });

  group('whether this device can record at all', () {
    test('a device that has never tried says it can', () async {
      // Silence has to read as ABLE. A device that answered "cannot" before it
      // had tried would rank itself last in the very first election of a call,
      // when nobody has tried anything yet, and every device would defer to
      // every other one.
      expect(service().canCapture, isTrue);
    });

    test(
      'a platform that answers there is no tap point stands it aside',
      () async {
        // The one answer that IS about the device. The election reads it and
        // hands the recording to a sibling that has somewhere to record from.
        final capture = service(withTap: _NoTap());
        await capture.start(track);

        expect(capture.isRecording, isFalse);
        expect(capture.canCapture, isFalse);
      },
    );

    test('a throw from the attach does not stand this device aside', () async {
      // A platform call that failed says this ATTEMPT failed. Reading it as a
      // statement about the device retires a working device over one bad round
      // trip, for the rest of the call, and hands the recording to a sibling
      // that may have no tap at all.
      final capture = service();
      track.failNextRenderer = true;

      await expectLater(capture.start(track), throwsStateError);

      expect(capture.canCapture, isTrue);
    });

    test('an attach that works again takes the answer back', () async {
      // A reading, not a latch. Android's tap point can be missing simply
      // because WebRTC's processing factory had not finished initialising, and
      // a device retired over that would never come back within the call.
      final tap = _RefusesUntilAskedAgainTap();
      final capture = service(withTap: tap);
      await capture.start(track);
      expect(capture.canCapture, isFalse);

      await capture.start(track);
      expect(capture.canCapture, isTrue);
      await capture.stop();
    });
  });

  group('a stretch another device also recorded', () {
    test('is dropped rather than delivered', () async {
      // Two devices answering the same ring both record the opening seconds.
      // The sink keys a result by capture session and chunk index, and two
      // devices are two sessions -- so delivering this tail credits the learner
      // twice for saying something once.
      final capture = service();
      await capture.start(track);
      track.emit(100);
      capture.setDiscardOnStop(true);

      await capture.stop();

      expect(sink.delivered, isEmpty);
    });

    test('does not take the stretch that follows it as well', () async {
      // The request belongs to the stretch the election decided it for. Left
      // standing it would silently drop a later tail that nobody else recorded.
      final capture = service();
      await capture.start(track);
      track.emit(100);
      capture.setDiscardOnStop(true);
      await capture.stop();
      expect(sink.delivered, isEmpty);

      await capture.start(track);
      track.emit(100);
      await capture.stop();

      expect(
        sink.delivered.map((c) => c.index),
        [1],
        reason: 'the discarded stretch still happened, so numbering moved on',
      );
    });

    test('survives a stop that does not settle its deliveries', () async {
      // Teardown's stop, which does not wait for what it handed over, and then
      // the finish that does. Neither of them carries the request, so a flush
      // reached that way has to find it where the election left it.
      //
      // The ordering claim itself -- that the request is in BEFORE the reconcile
      // that stops the tap -- belongs to the caller and is pinned by the
      // active_call test of that name. Nothing here goes through an election,
      // so nothing here could fail if that moved.
      final capture = service();
      await capture.start(track);
      track.emit(100);
      capture.setDiscardOnStop(true);

      await capture.stop(settleDeliveries: false);
      await capture.finish();

      expect(sink.delivered, isEmpty);
    });

    test('is not rewritten by an election that ran after the stop', () async {
      // The request is read at the FLUSH, and a stop reaches that only after up
      // to three bounded platform waits -- the detach, an overtaken start's
      // release, and the residue sweep. The election goes on running on its two
      // second clock throughout, and by then it is describing a roster with
      // nothing to do with the stretch being ended. Cleared inside that stall
      // it delivers the duplicate; set inside it, it drops the only copy of
      // what the learner said.
      final tap = _SlowDetachTap();
      final capture = service(
        withTap: tap,
        detach: const Duration(seconds: 30),
      );
      await capture.start(track);
      tap.onFrames!(speech(100), captureSampleRate, 1);
      // The election concluded displacement, and this stretch is a duplicate of
      // what a sibling already has.
      capture.setDiscardOnStop(true);

      final stopping = capture.stop();
      await pumpEventQueue();
      // The sibling hangs up while the detach is still deciding, so the next
      // tick elects this device again -- for a stretch that has not begun.
      capture.setDiscardOnStop(false);
      tap.finishDetach();
      await stopping;

      expect(sink.delivered, isEmpty);
    });
  });

  group('a release that is still deciding', () {
    // All three of these stand the same choreography up, because it is the one
    // window nothing else covers: `_running = true` is set BEFORE the open, so
    // two merely overlapping starts are refused on the running guard whether
    // or not a release is counted. What is needed is a release running with no
    // stop wrapped around it, and only one thing produces that -- a tap that
    // arrives after the stop it belonged to, which is let go outside the
    // memoised stop.
    Future<(CallCaptureService, _OvertakenTap)> midRelease() async {
      final tap = _OvertakenTap();
      // Long, so the release under test is still deciding rather than having
      // timed out and held the tap already.
      final s = service(withTap: tap, detach: const Duration(seconds: 30));
      // Left running deliberately: it is the start that gets overtaken, and it
      // does not finish until its own release does.
      unawaited(s.start(track));
      await pumpEventQueue();
      // Lands while the open is still pending. It finds no detach to take, so
      // it completes at once and clears the in-flight stop -- and from here
      // nothing serialises against what the open is about to hand back.
      await s.stop();
      tap.finishAttaching();
      await pumpEventQueue();
      return (s, tap);
    }

    test('refuses a start over the tap it has not placed yet', () async {
      // Across a release the tap it is working on is in NEITHER `_detach` nor
      // the unreleased list, so both readers answer "nothing attached" about a
      // tap that is still on the track. A start let past there lays a second
      // tap over the first and the learner's own voice is counted twice.
      final (s, tap) = await midRelease();

      await expectLater(s.start(track), throwsStateError);

      // And what the dying tap hands over on its way out belongs to nothing:
      // the stretch it was opened for is over and no stretch has replaced it.
      tap.onFrames!(speech(100), captureSampleRate, 1);
      tap.finishDetach();
      await pumpEventQueue();
      await s.stop();
      await pumpEventQueue();
      expect(
        sink.delivered,
        isEmpty,
        reason: 'a tap on its way out feeds no run at all',
      );
    });

    test('does not stand this device aside for a timing race', () async {
      // A release still deciding is a MILLISECOND, not a fact about the device:
      // nothing retries it, and it is cleared by the release finishing rather
      // than by anything this device could do about it. Blaming it would have a
      // stop that merely landed mid-attach retire a perfectly good device for
      // the rest of the call -- and the election would then hand the recording
      // to a sibling with no tap at all.
      final (s, tap) = await midRelease();

      await expectLater(s.start(track), throwsStateError);
      expect(s.canCapture, isTrue);

      tap.finishDetach();
      await pumpEventQueue();
      await s.stop();
    });

    test('is waited for by a stop, not stepped over', () async {
      // A stop that concludes "everything is off" while a release is still
      // deciding walks past the tap that release is about to hold. Only a stop
      // ever comes back to a held tap, so one held after the last stop of the
      // call is held for the rest of it -- and every later start refuses.
      final (s, tap) = await midRelease();

      final stopping = s.stop();
      await pumpEventQueue();
      // The detach finally answers, with a refusal. That is retryable, and the
      // retry belongs to the stop that is running right now.
      tap.failDetach();
      await stopping;

      expect(
        tap.detachAttempts,
        2,
        reason: 'the stop came back to the tap its own sweep would have missed',
      );
      await s.start(track);
      expect(s.isRecording, isTrue, reason: 'and nothing is left held');
    });
  });

  group('a tap that dies under a live recording', () {
    test('ends the stretch and says so', () async {
      // A tap can attach and then fail asynchronously, with nothing thrown and
      // nothing returned. Left alone the recorder holds a detach it reads as a
      // live recording for the rest of the call, over a tap that will never
      // deliver a frame, and the analytics go silently empty.
      final tap = _DyingTap();
      final s = service(withTap: tap);
      var lost = 0;
      s.onCaptureLost = () => lost++;
      await s.start(track);
      expect(s.isRecording, isTrue);

      tap.die();
      await pumpEventQueue();

      expect(s.isRecording, isFalse, reason: 'the stretch is over');
      expect(tap.detached, isTrue, reason: 'through the one release path');
      expect(lost, 1, reason: 'and whoever elects recorders was told');
    });

    test('does not end the stretch that replaced it', () async {
      // The report carries the session it was opened for, exactly as the frame
      // callback does. A tap that dies long after its own stretch ended must
      // not stop the one running now.
      final tap = _DyingTap();
      final s = service(withTap: tap);
      await s.start(track);
      final stale = tap.die;
      await s.stop();
      await s.start(track);

      var lost = 0;
      s.onCaptureLost = () => lost++;
      stale();
      await pumpEventQueue();

      expect(s.isRecording, isTrue, reason: 'the live stretch is untouched');
      expect(lost, 0);
      await s.stop();
    });

    test('flushes what the learner had already said', () async {
      // The tap died; the audio before it did not. Ending the stretch through
      // the ordinary stop is what puts that tail in front of the sink rather
      // than dropping it with the tap.
      final tap = _DyingTap();
      final s = service(withTap: tap);
      await s.start(track);
      tap.onFrames!(speech(100), captureSampleRate, 1);

      tap.die();
      await pumpEventQueue();

      expect(sink.delivered.map((c) => c.index), [0]);
    });

    test('lets a listener restart from inside the report', () async {
      // The stop goes first, and it sets the gate and publishes itself before
      // it awaits anything -- so a listener that starts again from straight
      // inside this call finds a stop to wait for. Reporting first would hand
      // that listener a recorder still marked as running, and its start would
      // bounce off the "already running" guard instead.
      final tap = _DyingTap();
      final s = service(withTap: tap);
      Future<void>? restarted;
      s.onCaptureLost = () => restarted = s.start(track);
      await s.start(track);

      tap.die();
      await pumpEventQueue();

      await expectLater(
        restarted,
        completes,
        reason: 'the restart queues behind the stop rather than racing it',
      );
      expect(s.isRecording, isTrue);
      await s.stop();
    });

    test('a report from a tap whose open then failed ends nothing', () async {
      // The session still matches -- a failed open does not move it -- so the
      // only thing standing between a dead run and a second teardown is the
      // check that a run is still going at all. Without it the death would
      // stop a recorder that is already idle and tell the election it had lost
      // a recording that never started.
      final tap = _DiesAfterFailedOpenTap();
      final s = service(withTap: tap);
      await expectLater(s.start(track), throwsStateError);
      var lost = 0;
      s.onCaptureLost = () => lost++;

      tap.die();
      await pumpEventQueue();

      expect(lost, 0, reason: 'there was no recording to lose');
      expect(s.isRecording, isFalse);
    });
  });

  group('a device whose tap keeps dying', () {
    /// What the owner of the election does with the report, reduced to the part
    /// that matters here: it clears its own record and elects again, and an
    /// election that ranks device ids alone hands the recording straight back
    /// to the device that just failed.
    void restartOnLoss(CallCaptureService s) =>
        s.onCaptureLost = () => unawaited(s.start(track));

    test('stops attaching once two attempts have died', () async {
      // Nothing differs between one attempt and the next: the same device
      // attaches the same tap for the same reason, so a third go is a spin
      // rather than a retry. On the web each turn builds and tears down an
      // AudioContext and an AudioWorklet module, for the rest of the call.
      final tap = _DyingTap();
      final s = service(withTap: tap);
      restartOnLoss(s);
      await s.start(track);

      for (var i = 0; i < 5; i++) {
        tap.die();
        await pumpEventQueue();
      }

      expect(tap.opens, 2, reason: 'the retry is bounded, not endless');
      expect(
        s.isRecording,
        isFalse,
        reason: 'and it says so rather than holding a tap it does not have',
      );
    });

    test('says so, so a capable sibling can out-rank it', () async {
      // The election reads this, and nothing else tells it. Without it a device
      // whose tap point is broken goes on announcing that it can record, keeps
      // winning the election on device id, and the call is transcribed by
      // nobody -- while `start` quietly returns having attached nothing. The
      // refusal to attach and the announcement have to move together.
      final tap = _DyingTap();
      final s = service(withTap: tap);
      restartOnLoss(s);
      await s.start(track);

      tap.die();
      await pumpEventQueue();
      expect(
        s.canCapture,
        isTrue,
        reason: 'one death is a transient; the second attempt IS the retry',
      );

      tap.die();
      await pumpEventQueue();
      expect(s.canCapture, isFalse);
    });

    test('a stretch that delivered audio starts the count again', () async {
      // Consecutive, not cumulative. A delivered frame is the one piece of
      // evidence available that this device's tap point works, so a death
      // hours later is a fresh failure and not the second half of an old one.
      final tap = _DyingTap();
      final s = service(withTap: tap);
      restartOnLoss(s);
      await s.start(track);

      tap.die();
      await pumpEventQueue();
      // The attach that replaced it works.
      tap.onFrames!(speech(100), captureSampleRate, 1);
      tap.die();
      await pumpEventQueue();

      expect(tap.opens, 3, reason: 'the working stretch bought a fresh count');
      expect(s.isRecording, isTrue);
      await s.stop();
    });
  });

  group('audio the tap could not hand over', () {
    test('is published, so the half stops reading clean over a hole', () async {
      // The platform drops a batch rather than queue without limit when every
      // spare buffer is in flight. Those frames never reach Dart, so they are
      // in none of the sink's counts -- and a half carrying only those counts
      // said chunksLost: 0 about a recording with a hole in it.
      final tap = _DrivableTap();
      final s = service(withTap: tap);
      await s.start(track);

      expect(s.captureDroppedMs, 0);
      tap.onFrames!(speech(100), captureSampleRate, 1, droppedMs: 300);
      tap.onFrames!(speech(100), captureSampleRate, 1, droppedMs: 200);
      await s.stop();

      expect(s.captureDroppedMs, 500);
    });

    test(
      'does not move the chunks after it earlier than they were spoken',
      () async {
        // The corruption. Every position is derived from a running frame count,
        // so frames that never arrived used to pull each later chunk back by the
        // whole of what went -- on a half that also declares its positions
        // pinned, which is a wrong answer stated with confidence.
        final tap = _DrivableTap();
        final s = service(withTap: tap);
        await s.start(track);
        final runStart = clock.ms - 100;

        tap.onFrames!(speech(100), captureSampleRate, 1);
        clock.pass(100);
        // 800ms is the platform's whole spare set, which is what a drop means.
        tap.onFrames!(speech(100), captureSampleRate, 1, droppedMs: 800);
        clock.pass(100);
        await s.stop();
        await pumpEventQueue();

        expect(sink.delivered, hasLength(2));
        expect(
          sink.delivered.first.startedAtMs,
          runStart,
          reason: 'the audio before the gap is where it always was',
        );
        expect(
          sink.delivered.last.startedAtMs,
          runStart + 100 + 800,
          reason: 'a hundred milliseconds of speech, then the gap',
        );
      },
    );

    test('cuts at the gap rather than gluing across it', () async {
      // Two stretches of speech with 800ms of missing time between them must
      // not arrive as one chunk of contiguous bytes: a word timing inside that
      // chunk is measured from its start, so everything after the seam would
      // be reported 800ms early with nothing to say where the seam was.
      final tap = _DrivableTap();
      final s = service(withTap: tap);
      await s.start(track);

      tap.onFrames!(speech(100), captureSampleRate, 1);
      tap.onFrames!(speech(100), captureSampleRate, 1, droppedMs: 800);
      await s.stop();
      await pumpEventQueue();

      expect(
        sink.delivered.map((c) => c.duration.inMilliseconds),
        [100, 100],
        reason: 'glued, this would be one 200ms chunk',
      );
    });

    test(
      'is counted but not placed when no run is open to place it in',
      () async {
        // A gap reported on the frame that STARTS a run sits before the run
        // began, and the run is placed from a clock read at that same frame --
        // a reading already taken after the gap. Skipping it into the new
        // chunker would move the run later than the speech it holds.
        final tap = _DrivableTap();
        final s = service(withTap: tap);
        await s.start(track);

        tap.onFrames!(speech(100), captureSampleRate, 1, droppedMs: 400);
        await s.stop();
        await pumpEventQueue();

        expect(s.captureDroppedMs, 400);
        expect(runStarts.single, clock.ms - 100);
        expect(sink.delivered.single.startedAtMs, clock.ms - 100);
      },
    );

    test('an ordinary frame reports no gap and moves nothing', () async {
      // Every frame carries this number, a hundred times a second, and almost
      // all of them carry a zero. A zero must not cut a chunk.
      final tap = _DrivableTap();
      final s = service(withTap: tap);
      await s.start(track);

      tap.onFrames!(speech(100), captureSampleRate, 1, droppedMs: 0);
      tap.onFrames!(speech(100), captureSampleRate, 1);
      await s.stop();
      await pumpEventQueue();

      expect(s.captureDroppedMs, 0);
      expect(sink.delivered.single.duration.inMilliseconds, 200);
    });

    test('a gap arriving after the stretch ended is not taken', () async {
      // The same gate every other frame passes. Audio dropped after a hangup
      // belongs to no stretch, and counting it would put a gap on a half for a
      // stretch that had already been flushed and published.
      final tap = _DrivableTap();
      final s = service(withTap: tap);
      await s.start(track);
      final leaked = tap.onFrames!;

      tap.onFrames!(speech(100), captureSampleRate, 1);
      await s.stop();
      leaked(speech(100), captureSampleRate, 1, droppedMs: 900);

      expect(s.captureDroppedMs, 0);
    });
  });

  group('the tail of a stretch another device also recorded', () {
    test('is recorded on the sink rather than only logged', () async {
      // The one decision in this path that destroys audio outright, and it
      // rests entirely on a claim about a device we cannot see. Logged alone,
      // the half read clean: the chunk was in no count, so nothing downstream
      // could check the claim in either direction.
      final capture = service();
      await capture.start(track);
      track.emit(100);
      capture.setDiscardOnStop(true);

      await capture.stop();

      expect(sink.delivered, isEmpty);
      expect(
        sink.discardedChunks.map((c) => c.index),
        [0],
        reason: 'the sibling half should show a chunk 0 against this',
      );
    });

    test('a delivered tail is not reported as discarded', () async {
      final capture = service();
      await capture.start(track);
      track.emit(100);

      await capture.stop();

      expect(sink.delivered, hasLength(1));
      expect(sink.discardedChunks, isEmpty);
    });
  });
}

/// A device that offers no point to read from after echo cancellation.
/// A tap whose detach hangs until released, and whose frame callback the test
/// can drive by hand — to deliver frames WHILE the detach is stuck.
class _SlowDetachTap implements CallAudioTap {
  CallAudioFrames? onFrames;
  final _detaching = Completer<void>();
  void finishDetach() => _detaching.complete();
  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    this.onFrames = onFrames;
    return () => _detaching.future;
  }
}

/// A tap point that is not there the first time and is there the second, which
/// is what Android's processing factory looks like when the first call of a
/// session reaches it before WebRTC has finished initialising.
class _RefusesUntilAskedAgainTap implements CallAudioTap {
  int opens = 0;

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async => ++opens == 1 ? null : () async {};
}

/// A tap that refuses the first detach outright and takes its time over the
/// second, which is the only shape that leaves a release DECIDING inside a
/// start's residue retry.
class _FreesOnRetryTap implements CallAudioTap {
  int opens = 0;
  int detachAttempts = 0;
  final _freeing = Completer<void>();

  void finishDetach() => _freeing.complete();

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    opens++;
    return () {
      detachAttempts++;
      // Twice, because the stop that first asks retries the residue itself
      // before it returns. The third ask is the one a START makes.
      if (detachAttempts <= 2) throw StateError('not yet');
      return _freeing.future;
    };
  }
}

class _NoTap implements CallAudioTap {
  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async => null;
}

/// A tap whose detach takes a moment, which is what opens the window for a
/// second stop to arrive while the first is still unwinding.
class _SlowTap implements CallAudioTap {
  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async =>
      () async => Future<void>.delayed(const Duration(milliseconds: 20));
}

/// A tap that hands over its last audio only as it is detached, the way the
/// platform one does.
class _TailOnDetachTap implements CallAudioTap {
  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    return () async {
      onFrames(Int16List.fromList(List<int>.filled(8000, 1200)), 16000, 1);
    };
  }
}

/// A tap that takes its time attaching, so a stop can land inside it.
/// Attaches slowly, and will not let go the first time it is asked.
/// A tap whose detach throws before it returns anything at all.
class _ThrowsOnDetachTap implements CallAudioTap {
  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async =>
      () => throw StateError('the platform refused, immediately');
}

/// A tap whose detach never comes back — a platform call that has gone away.
class _SilentDetachTap implements CallAudioTap {
  int detachCalls = 0;

  /// Completed by a test to let the outstanding detach finally finish.
  final finish = Completer<void>();

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async => () {
    detachCalls++;
    return finish.future;
  };
}

class _StubbornSlowTap implements CallAudioTap {
  final _attached = Completer<void>();
  int detachAttempts = 0;
  bool detached = false;

  void finishAttaching() => _attached.complete();

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    await _attached.future;
    return () async {
      detachAttempts++;
      if (detachAttempts == 1) {
        throw StateError('the platform would not let go');
      }
      detached = true;
    };
  }
}

/// A tap the test drives by hand, so it can deliver audio at a rate of its own
/// choosing — which is what a device changing its capture rate mid-call looks
/// like from in here.
class _DrivableTap implements CallAudioTap {
  CallAudioFrames? onFrames;

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    this.onFrames = onFrames;
    return () async => this.onFrames = null;
  }
}

/// A tap that hands over audio and only THEN fails to open.
///
/// The platform was already delivering microphone samples; only the handshake
/// failed. The FIRST open behaves that way and a later one attaches normally,
/// so one test can cover a failed open landing after a new run has started.
class _FramesThenFailsTap implements CallAudioTap {
  final _failing = Completer<void>();
  int opens = 0;

  /// The callback of the most recent open, so a test can keep feeding the run
  /// that is actually current.
  CallAudioFrames? onFrames;

  void finishOpening() => _failing.complete();

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    this.onFrames = onFrames;
    onFrames(speech(100), captureSampleRate, 1);
    if (opens++ > 0) return () async {};
    await _failing.future;
    throw StateError('the platform never finished opening');
  }
}

/// A tap whose open throws AFTER installing its callback.
///
/// There is no detach handle to hold, so nothing ever comes back to it: it goes
/// on delivering audio into a recorder that believes it is gone.
class _LeakingTap implements CallAudioTap {
  CallAudioFrames? onFrames;
  int opens = 0;

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    this.onFrames ??= onFrames;
    if (opens++ > 0) return () async {};
    throw StateError('the platform refused after installing the callback');
  }
}

class _SlowToAttachTap implements CallAudioTap {
  final _attached = Completer<void>();
  bool detached = false;

  void finishAttaching() => _attached.complete();

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    await _attached.future;
    return () async => detached = true;
  }
}

/// A tap that attaches only when told to, and then will not let go until told
/// again — so a test can hold a release open and act while it is deciding.
///
/// Its frame callback is kept from before the attach completed, because what
/// the platform hands over on its way out is part of what a release has to get
/// right.
class _OvertakenTap implements CallAudioTap {
  final _attached = Completer<void>();
  Completer<void> _detaching = Completer<void>();
  CallAudioFrames? onFrames;
  int detachAttempts = 0;

  void finishAttaching() => _attached.complete();

  void finishDetach() => _detaching.complete();

  /// The detach finally answers, with a refusal. Nothing is left in flight, so
  /// this is the one case where asking again is safe — and the second ask
  /// succeeds, so a test can tell "came back to it" from "gave up on it".
  void failDetach() {
    final refusing = _detaching;
    _detaching = Completer<void>()..complete();
    refusing.completeError(StateError('the platform would not let go'));
  }

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    this.onFrames = onFrames;
    await _attached.future;
    return () {
      detachAttempts++;
      return _detaching.future;
    };
  }
}

/// A tap that attaches cleanly and then dies where nobody asked it to, which is
/// what a renderer whose capture failed asynchronously does.
class _DyingTap implements CallAudioTap {
  CallAudioFrames? onFrames;
  bool detached = false;

  /// How many times this tap has been attached, which is the only thing a test
  /// can see about a recorder that keeps trying.
  int opens = 0;

  /// The report the tap was handed, so a test can fire it at a moment of its
  /// choosing — including long after the stretch it belonged to ended.
  late TapDied die;

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    opens++;
    this.onFrames = onFrames;
    die = onDead;
    return () async => detached = true;
  }
}

/// A tap that takes the report and THEN fails to open.
///
/// Nothing shipped does this today — the renderer cannot throw once it has
/// armed, and the Android tap never reports at all — but the contract permits
/// it, and it is the one shape that produces a report whose session still
/// matches a run that is already over.
class _DiesAfterFailedOpenTap implements CallAudioTap {
  late TapDied die;

  @override
  Future<DetachTap?> open(
    AudioTrack track,
    CallAudioFrames onFrames, {
    required TapDied onDead,
  }) async {
    die = onDead;
    throw StateError('the platform refused after taking the report');
  }
}
