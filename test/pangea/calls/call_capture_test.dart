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

      // Still attached, so a second recording must not be laid over the top of
      // it — two taps feeding one chunker would count the learner twice.
      await expectLater(capture.start(track), throwsStateError);

      // And the next stop comes back to it. Nothing else ever does.
      await capture.stop();
      expect(tap.detached, isTrue, reason: 'the tap was released in the end');
      await capture.start(track);
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
  Future<DetachTap?> open(AudioTrack track, CallAudioFrames onFrames) async {
    this.onFrames = onFrames;
    return () => _detaching.future;
  }
}

class _NoTap implements CallAudioTap {
  @override
  Future<DetachTap?> open(AudioTrack track, CallAudioFrames onFrames) async =>
      null;
}

/// A tap whose detach takes a moment, which is what opens the window for a
/// second stop to arrive while the first is still unwinding.
class _SlowTap implements CallAudioTap {
  @override
  Future<DetachTap?> open(AudioTrack track, CallAudioFrames onFrames) async =>
      () async => Future<void>.delayed(const Duration(milliseconds: 20));
}

/// A tap that hands over its last audio only as it is detached, the way the
/// platform one does.
class _TailOnDetachTap implements CallAudioTap {
  @override
  Future<DetachTap?> open(AudioTrack track, CallAudioFrames onFrames) async {
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
  Future<DetachTap?> open(AudioTrack track, CallAudioFrames onFrames) async =>
      () => throw StateError('the platform refused, immediately');
}

/// A tap whose detach never comes back — a platform call that has gone away.
class _SilentDetachTap implements CallAudioTap {
  int detachCalls = 0;

  /// Completed by a test to let the outstanding detach finally finish.
  final finish = Completer<void>();

  @override
  Future<DetachTap?> open(AudioTrack track, CallAudioFrames onFrames) async =>
      () {
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
  Future<DetachTap?> open(AudioTrack track, CallAudioFrames onFrames) async {
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
  Future<DetachTap?> open(AudioTrack track, CallAudioFrames onFrames) async {
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
  Future<DetachTap?> open(AudioTrack track, CallAudioFrames onFrames) async {
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
  Future<DetachTap?> open(AudioTrack track, CallAudioFrames onFrames) async {
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
  Future<DetachTap?> open(AudioTrack track, CallAudioFrames onFrames) async {
    await _attached.future;
    return () async => detached = true;
  }
}
