import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:pangea_call_capture/pangea_call_capture.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_tap.dart';

import 'package:livekit_client/livekit_client.dart'
    show
        AudioFormat,
        AudioFrame,
        AudioFrameCallback,
        AudioRendererOptions,
        AudioTrack,
        CancelListenFunc;

/// A platform side that can be made to behave the ways a real one does.
class FakeCapture extends PangeaCallCapture {
  late final StreamController<CallAudioFrame> _frames =
      StreamController<CallAudioFrame>.broadcast(
        onCancel: () => teardown.add('cancel'),
      );
  final bool attaches;
  final Object? startThrows;

  /// How many of the FIRST attempts throw before the platform starts giving
  /// clean answers. Models the case the ladder exists for: a processing factory
  /// that is still initialising when the first call of a session reaches it.
  final int throwsUntilAttempt;
  int starts = 0;
  int stops = 0;

  FakeCapture({
    this.attaches = true,
    this.startThrows,
    this.throwsUntilAttempt = 0,
  });

  @override
  Stream<CallAudioFrame> get frames => _frames.stream;

  @override
  Future<bool> start() async {
    starts++;
    if (starts <= throwsUntilAttempt) {
      throw StateError('the processing factory is not up yet');
    }
    if (startThrows != null) throw startThrows!;
    return attaches;
  }

  /// The order teardown actually happened in.
  final List<String> teardown = [];

  @override
  Future<void> stop({bool settleDeliveries = true}) async {
    teardown.add('stop');
    // Deferred on purpose. A stop that completes synchronously cannot tell a
    // detach that was awaited from one that was merely started.
    await Future<void>.delayed(Duration.zero);
    stops++;
  }

  bool get watching => _frames.hasListener;

  Future<void> emit(List<int> samples, int rate) async {
    final bytes = Uint8List(samples.length * 2);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < samples.length; i++) {
      view.setInt16(i * 2, samples[i], Endian.little);
    }
    _frames.add(CallAudioFrame(pcm16: bytes, sampleRate: rate));
    await pumpEventQueue();
  }
}

void main() {
  group('the rate a frame is labelled with', () {
    // The browser is free to refuse the rate we ask an AudioContext for, and
    // the renderer then reports the rate it really got (48 kHz by default).
    // Labelling those samples 16 kHz because 16 kHz is what we requested is
    // silent corruption: the audio transcribes as gibberish.
    test('is the rate the frame arrived at, not the rate we asked for', () {
      const tap = TrackRendererTap(sampleRate: 16000, channels: 1);
      int? reported;
      TrackRendererTap.deliver(
        AudioFrame(
          sampleRate: 48000,
          channels: 1,
          data: Uint8List.fromList([0, 0, 1, 0]),
          format: AudioFormat.Int16,
        ),
        (samples, rate, channels, {droppedMs = 0}) => reported = rate,
      );
      expect(tap.sampleRate, 16000, reason: 'we still REQUEST 16 kHz');
      expect(reported, 48000, reason: 'but we report what actually arrived');
    });

    test('reports the CHANNEL COUNT the frame arrived with', () {
      // The count used to be dropped one line after the comment above argued
      // the case for the rate. On native it is read straight off the platform's
      // own event, exactly as the rate is, and nothing promises it matches what
      // we asked for -- so a stereo frame labelled mono would halve the frame
      // count taken from its byte length and warp both the audio and every
      // duration derived from it.
      const tap = TrackRendererTap(sampleRate: 16000, channels: 1);
      int? reported;
      TrackRendererTap.deliver(
        AudioFrame(
          sampleRate: 48000,
          channels: 2,
          data: Uint8List.fromList([0, 0, 1, 0, 2, 0, 3, 0]),
          format: AudioFormat.Int16,
        ),
        (samples, rate, channels, {droppedMs = 0}) => reported = channels,
      );
      expect(tap.channels, 1, reason: 'we still REQUEST mono');
      expect(reported, 2, reason: 'but we report what actually arrived');
    });

    test('a renderer that honours the request reports mono', () {
      // The web renderer downmixes to what was asked for, so the two agree
      // there. The rule must not fire on that ordinary case.
      int? reported;
      TrackRendererTap.deliver(
        AudioFrame(
          sampleRate: 16000,
          channels: 1,
          data: Uint8List.fromList([0, 0]),
          format: AudioFormat.Int16,
        ),
        (samples, rate, channels, {droppedMs = 0}) => reported = channels,
      );
      expect(reported, 1);
    });

    test('a browser that honours the request reports that rate', () {
      int? reported;
      TrackRendererTap.deliver(
        AudioFrame(
          sampleRate: 16000,
          channels: 1,
          data: Uint8List.fromList([0, 0]),
          format: AudioFormat.Int16,
        ),
        (samples, rate, channels, {droppedMs = 0}) => reported = rate,
      );
      expect(reported, 16000);
    });
  });

  group('the tap Android records through', () {
    test('delivers samples and the rate they were captured at', () async {
      final platform = FakeCapture();
      final tap = PostEchoCancellationTap(capture: platform);
      final got = <(Int16List, int)>[];

      final detach = await tap.open(
        _noTrack,
        (s, r, c, {droppedMs = 0}) => got.add((s, r)),
        onDead: () {},
      );
      await platform.emit([1, -1, 32767, -32768], 48000);

      expect(detach, isNotNull);
      expect(got, hasLength(1));
      expect(got.single.$1, [1, -1, 32767, -32768]);
      expect(
        got.single.$2,
        48000,
        reason: 'the rate is not fixed, so it travels with the audio',
      );
    });

    test(
      'reports no tap rather than pretending, when it cannot attach',
      () async {
        // Recording nothing costs analytics. Failing here would cost the call.
        final platform = FakeCapture(attaches: false);
        final tap = PostEchoCancellationTap(capture: platform);

        final detach = await tap.open(
          _noTrack,
          (_, _, _, {droppedMs = 0}) {},
          onDead: () {},
        );

        expect(detach, isNull);
        expect(
          platform.watching,
          isFalse,
          reason: 'and nothing is left subscribed',
        );
      },
    );

    test(
      'a platform that only ever threw rethrows rather than answering null',
      () async {
        // A null is a statement about the DEVICE -- there is no tap point here --
        // and the recorder stands the device aside for the rest of the call on
        // it, so a sibling takes over. A platform call that failed says nothing of
        // the kind: it says this attempt failed. Answering null there retired a
        // perfectly good device over one bad round trip.
        final platform = FakeCapture(startThrows: StateError('no webrtc yet'));
        final tap = PostEchoCancellationTap(capture: platform);

        await expectLater(
          tap.open(_noTrack, (_, _, _, {droppedMs = 0}) {}, onDead: () {}),
          throwsStateError,
        );
        expect(platform.starts, 3, reason: 'and it did try the whole ladder');
        expect(platform.watching, isFalse);
      },
    );

    test('a platform that threw and then plainly refused answers null', () async {
      // The error was not the reason in the end. Three refusals is the device
      // answering, and an earlier stumble on the way there must not turn that
      // answer into a throw -- which would leave the recorder retrying a device
      // that has already said no, every two seconds, for the whole call.
      final platform = FakeCapture(attaches: false, throwsUntilAttempt: 1);
      final tap = PostEchoCancellationTap(capture: platform);

      final detach = await tap.open(
        _noTrack,
        (_, _, _, {droppedMs = 0}) {},
        onDead: () {},
      );

      expect(detach, isNull);
      expect(platform.watching, isFalse);
    });

    test('a build with no plugin at all answers null immediately', () async {
      // The one error that IS an answer about the device: there is no such
      // plugin in this build, so there is nothing a retry could find and
      // nothing to spend four seconds of the opening of a call waiting for.
      final platform = FakeCapture(
        startThrows: MissingPluginException('no pangea_call_capture here'),
      );
      final tap = PostEchoCancellationTap(capture: platform);

      final detach = await tap.open(
        _noTrack,
        (_, _, _, {droppedMs = 0}) {},
        onDead: () {},
      );

      expect(detach, isNull);
      expect(
        platform.starts,
        1,
        reason: 'answered at once rather than climbing the ladder',
      );
      expect(platform.watching, isFalse);
    });

    test('stops the platform before it stops listening', () async {
      // Setup subscribes and then starts, so teardown stops and then cancels.
      // Cancelling first throws away whatever has been handed over but not yet
      // delivered, which at a hangup is the last thing the learner said.
      final platform = FakeCapture();
      final tap = PostEchoCancellationTap(capture: platform);

      final detach = await tap.open(
        _noTrack,
        (_, _, _, {droppedMs = 0}) {},
        onDead: () {},
      );
      await detach!.call();

      expect(platform.teardown.first, 'stop');
    });

    test('detaching stops the platform and the subscription', () async {
      final platform = FakeCapture();
      final tap = PostEchoCancellationTap(capture: platform);

      final detach = await tap.open(
        _noTrack,
        (_, _, _, {droppedMs = 0}) {},
        onDead: () {},
      );
      // Awaited with nothing pumped afterwards: a detach that only schedules the
      // work would leave the tap attached at the moment the caller believes the
      // recording has stopped.
      await detach!.call();

      expect(platform.stops, 1);
      expect(platform.watching, isFalse);
    });

    test('listens only AFTER the platform attach is owned', () async {
      // The reverse of the ordering this test used to pin. The frame stream is
      // SHARED, so a subscription taken before attach belongs to nobody -- and
      // a stale, overtaken open() sleeping in its retry went on feeding the
      // same pipeline beside the live recording, double-counting the opening
      // of the next call. Subscribing only once the attach is owned costs the
      // few frames between the attach answer and the listen; feeding audio
      // into analytics twice is the thing that must be impossible.
      var listeningWhenStarted = false;
      final platform = _OrderingCapture(() => listeningWhenStarted = true);

      await PostEchoCancellationTap(
        capture: platform,
      ).open(_noTrack, (_, _, _, {droppedMs = 0}) {}, onDead: () {});

      expect(
        listeningWhenStarted,
        isFalse,
        reason: 'nothing may listen before the attach is owned',
      );
      expect(
        platform.watching,
        isTrue,
        reason: 'and the owned attach is being listened to afterwards',
      );
    });

    test('a refused attach leaves no subscription behind', () async {
      final platform = FakeCapture(attaches: false);
      final detach = await PostEchoCancellationTap(
        capture: platform,
      ).open(_noTrack, (_, _, _, {droppedMs = 0}) {}, onDead: () {});
      expect(detach, isNull);
      expect(
        platform.watching,
        isFalse,
        reason: 'a stale listener beside a later live one is the defect',
      );
    });
  });

  group('how long a renderer is given to deliver its first frame', () {
    test('is longer than the package spends before it can deliver', () {
      // The budget belongs to the SETUP this watches, not to the interval
      // between frames once a capture runs. addAudioRenderer registers
      // synchronously and leaves livekit_client building the graph behind it,
      // and on the web that build OPENS by waiting up to three seconds on an
      // AudioContext resume the browser is allowed to stall. A budget equal to
      // that stall alone -- which is what this was -- reports a healthy attach
      // dead at the exact moment the package logs "continuing setup", and the
      // restart pays the identical cost and is killed at the identical point.
      const tap = TrackRendererTap(sampleRate: 16000, channels: 1);

      expect(
        tap.firstFrameTimeout,
        greaterThanOrEqualTo(rendererStartupStall * 3),
        reason:
            'the stall is only where the setup STARTS -- the worklet module '
            'and the graph come after it, so clearing it by a hair is not '
            'clearing it',
      );
    });
  });

  group('a renderer that attaches and then stays silent', () {
    /// Short enough that the tests need not wait a real attach out.
    const soon = Duration(milliseconds: 10);
    const wellPast = Duration(milliseconds: 60);

    TrackRendererTap watching() => const TrackRendererTap(
      sampleRate: 16000,
      channels: 1,
      firstFrameTimeout: soon,
    );

    test('is reported, rather than passing for a live recording', () async {
      // addAudioRenderer registers synchronously and starts the capture that
      // feeds it asynchronously inside livekit_client. When that capture fails
      // the package logs and goes quiet: nothing throws, nothing is returned,
      // and open() hands back a detach anyway. The recorder then reads the
      // attach as live and goes on believing it is recording for the whole
      // call, over a renderer that will never deliver a frame.
      final track = _RendererTrack();
      var deaths = 0;

      await watching().open(
        track,
        (_, _, _, {droppedMs = 0}) {},
        onDead: () => deaths++,
      );
      await Future<void>.delayed(wellPast);

      expect(deaths, 1, reason: 'the silence has to become an event');
    });

    test('a delivered frame disarms it', () async {
      // The other half of the same line. Reporting a working attach dead would
      // stand a healthy device aside from every later election.
      final track = _RendererTrack();
      var deaths = 0;

      await watching().open(
        track,
        (_, _, _, {droppedMs = 0}) {},
        onDead: () => deaths++,
      );
      track.emit();
      await Future<void>.delayed(wellPast);

      expect(deaths, 0);
    });

    test('a frame delivered inside the attach disarms it too', () async {
      // A renderer may call back before addAudioRenderer has even returned, so
      // the disarm can happen before there is a timer to disarm. Arming one
      // afterwards would report a device dead for want of a frame it had
      // already delivered.
      final track = _RendererTrack(deliverDuringAttach: true);
      var deaths = 0;

      await watching().open(
        track,
        (_, _, _, {droppedMs = 0}) {},
        onDead: () => deaths++,
      );
      await Future<void>.delayed(wellPast);

      expect(deaths, 0);
    });

    test('an ordinary detach before the first frame reports nothing', () async {
      // A stretch of recording short enough to end before its first frame is
      // not a failure. Reporting one would cost the device the next election
      // over a recording that was stopped on purpose.
      final track = _RendererTrack();
      var deaths = 0;

      final detach = await watching().open(
        track,
        (_, _, _, {droppedMs = 0}) {},
        onDead: () => deaths++,
      );
      await detach!.call();
      await Future<void>.delayed(wellPast);

      expect(deaths, 0);
    });

    test('reports without letting the tap go itself', () async {
      // The report is all this does. Releasing a tap is the caller's single
      // release path, and a renderer cancelled from in here as well is
      // cancelled twice -- neither guaranteed idempotent nor guaranteed to
      // answer the second time.
      final track = _RendererTrack();
      var deaths = 0;

      final detach = await watching().open(
        track,
        (_, _, _, {droppedMs = 0}) {},
        onDead: () => deaths++,
      );
      await Future<void>.delayed(wellPast);
      expect(deaths, 1, reason: 'it did report');

      await detach!.call();
      expect(
        track.cancels,
        1,
        reason: 'and the caller performed the one and only detach',
      );
    });
  });
}

/// The Android tap never touches the track it is given: the audio comes from the
/// processing module, not from this object.
final _noTrack = _UnusedTrack();

class _UnusedTrack implements AudioTrack {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A track whose renderer really registers and whose cancel really cancels.
///
/// [_UnusedTrack] cannot stand in for this: its noSuchMethod throws, so
/// [TrackRendererTap.open] itself had never been exercised at all -- only the
/// static frame conversion beside it.
class _RendererTrack implements AudioTrack {
  /// Whether the renderer calls back from INSIDE addAudioRenderer, before it
  /// has returned. Real ones may.
  final bool deliverDuringAttach;

  _RendererTrack({this.deliverDuringAttach = false});

  AudioFrameCallback? _onFrame;
  int cancels = 0;

  @override
  CancelListenFunc addAudioRenderer({
    required AudioFrameCallback onFrame,
    AudioRendererOptions options = const AudioRendererOptions(),
  }) {
    _onFrame = onFrame;
    if (deliverDuringAttach) emit();
    return () async {
      cancels++;
      _onFrame = null;
    };
  }

  void emit() => _onFrame?.call(
    AudioFrame(
      sampleRate: 16000,
      channels: 1,
      data: Uint8List.fromList([0, 0, 1, 0]),
      format: AudioFormat.Int16,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Records whether anything was listening at the moment start() was called.
class _OrderingCapture extends PangeaCallCapture {
  final _frames = StreamController<CallAudioFrame>.broadcast();
  final void Function() onStart;

  _OrderingCapture(this.onStart);

  @override
  Stream<CallAudioFrame> get frames => _frames.stream;

  @override
  Future<bool> start() async {
    if (_frames.hasListener) onStart();
    return true;
  }

  bool get watching => _frames.hasListener;

  @override
  Future<void> stop({bool settleDeliveries = true}) async {}
}
