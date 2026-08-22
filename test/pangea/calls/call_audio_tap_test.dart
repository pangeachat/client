import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart'
    show AudioFormat, AudioFrame, AudioTrack;
import 'package:pangea_call_capture/pangea_call_capture.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_tap.dart';

/// A platform side that can be made to behave the ways a real one does.
class FakeCapture extends PangeaCallCapture {
  late final StreamController<CallAudioFrame> _frames =
      StreamController<CallAudioFrame>.broadcast(
        onCancel: () => teardown.add('cancel'),
      );
  final bool attaches;
  final Object? startThrows;
  int starts = 0;
  int stops = 0;

  FakeCapture({this.attaches = true, this.startThrows});

  @override
  Stream<CallAudioFrame> get frames => _frames.stream;

  @override
  Future<bool> start() async {
    starts++;
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
        (samples, rate) => reported = rate,
      );
      expect(tap.sampleRate, 16000, reason: 'we still REQUEST 16 kHz');
      expect(reported, 48000, reason: 'but we report what actually arrived');
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
        (samples, rate) => reported = rate,
      );
      expect(reported, 16000);
    });
  });

  group('the tap Android records through', () {
    test('delivers samples and the rate they were captured at', () async {
      final platform = FakeCapture();
      final tap = PostEchoCancellationTap(capture: platform);
      final got = <(Int16List, int)>[];

      final detach = await tap.open(_noTrack, (s, r) => got.add((s, r)));
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

        final detach = await tap.open(_noTrack, (_, _) {});

        expect(detach, isNull);
        expect(
          platform.watching,
          isFalse,
          reason: 'and nothing is left subscribed',
        );
      },
    );

    test('a platform that throws is no tap either', () async {
      final platform = FakeCapture(startThrows: StateError('no webrtc yet'));
      final tap = PostEchoCancellationTap(capture: platform);

      final detach = await tap.open(_noTrack, (_, _) {});

      expect(detach, isNull);
      expect(platform.watching, isFalse);
    });

    test('stops the platform before it stops listening', () async {
      // Setup subscribes and then starts, so teardown stops and then cancels.
      // Cancelling first throws away whatever has been handed over but not yet
      // delivered, which at a hangup is the last thing the learner said.
      final platform = FakeCapture();
      final tap = PostEchoCancellationTap(capture: platform);

      final detach = await tap.open(_noTrack, (_, _) {});
      await detach!.call();

      expect(platform.teardown.first, 'stop');
    });

    test('detaching stops the platform and the subscription', () async {
      final platform = FakeCapture();
      final tap = PostEchoCancellationTap(capture: platform);

      final detach = await tap.open(_noTrack, (_, _) {});
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
      ).open(_noTrack, (_, _) {});

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
      ).open(_noTrack, (_, _) {});
      expect(detach, isNull);
      expect(
        platform.watching,
        isFalse,
        reason: 'a stale listener beside a later live one is the defect',
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
