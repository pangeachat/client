import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show AudioTrack;
import 'package:pangea_call_capture/pangea_call_capture.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_tap.dart';

/// A platform side that can be made to behave the ways a real one does.
class FakeCapture extends PangeaCallCapture {
  final _frames = StreamController<CallAudioFrame>.broadcast();
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

  @override
  Future<void> stop() async {
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

    test('listens before asking the platform to start', () async {
      // The other order drops whatever arrives in between, which on a busy
      // device is the opening words of the call.
      var listeningWhenStarted = false;
      final platform = _OrderingCapture(() => listeningWhenStarted = true);

      await PostEchoCancellationTap(
        capture: platform,
      ).open(_noTrack, (_, _) {});

      expect(listeningWhenStarted, isTrue);
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

  @override
  Future<void> stop() async {}
}
