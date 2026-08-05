import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/stt_audio_capture.dart';

/// A fake [RecordPlatform] swapped in for [RecordPlatform.instance] so the
/// capture can be driven with no real microphone. Only the members the capture
/// touches are implemented; anything else routes through [noSuchMethod] (the
/// standard platform-interface test pattern) and is never called here.
class _FakeRecordPlatform extends RecordPlatform {
  bool permission = true;
  RecordConfig? lastConfig;
  final StreamController<Uint8List> frames =
      StreamController<Uint8List>.broadcast();

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId) async => permission;

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    lastConfig = config;
    return frames.stream;
  }

  @override
  Future<String?> stop(String recorderId) async => null;

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late RecordPlatform original;
  late _FakeRecordPlatform fake;

  setUp(() {
    original = RecordPlatform.instance;
    fake = _FakeRecordPlatform();
    RecordPlatform.instance = fake;
  });

  tearDown(() {
    RecordPlatform.instance = original;
  });

  test(
    'start requests PCM16 / 16kHz / mono with echo-cancel + noise-suppress',
    () async {
      final capture = SttAudioCapture();

      final started = await capture.start((_) {});

      expect(started, isTrue);
      expect(capture.isRunning, isTrue);
      final cfg = fake.lastConfig!;
      expect(cfg.encoder, AudioEncoder.pcm16bits);
      expect(cfg.sampleRate, 16000);
      expect(cfg.numChannels, 1);
      expect(cfg.echoCancel, isTrue);
      expect(cfg.noiseSuppress, isTrue);

      await capture.dispose();
    },
  );

  test(
    'start returns false and never opens a stream when permission denied',
    () async {
      fake.permission = false;
      final capture = SttAudioCapture();

      final started = await capture.start((_) {});

      expect(started, isFalse);
      expect(capture.isRunning, isFalse);
      expect(fake.lastConfig, isNull);

      await capture.dispose();
    },
  );

  test('forwards each captured PCM frame to the onFrame callback', () async {
    final capture = SttAudioCapture();
    final received = <Uint8List>[];

    await capture.start(received.add);
    fake.frames.add(Uint8List.fromList(<int>[1, 2, 3]));
    fake.frames.add(Uint8List.fromList(<int>[4, 5, 6]));
    await pumpEventQueue();

    expect(received, hasLength(2));
    expect(received.first, equals(Uint8List.fromList(<int>[1, 2, 3])));

    await capture.dispose();
  });

  test('start is re-entrancy guarded (a second start is a no-op)', () async {
    final capture = SttAudioCapture();

    final first = await capture.start((_) {});
    final second = await capture.start((_) {});

    expect(first, isTrue);
    expect(second, isTrue);
    expect(capture.isRunning, isTrue);

    await capture.dispose();
  });

  // `SttAudioCapture.start` attaches `onError` to its subscription, but because
  // `record 6.1.2` re-wraps the platform stream and forwards DATA ONLY, a
  // mid-stream platform error is swallowed inside `record` and never reaches
  // that hook. So there is no claim here that a mid-stream mic death is caught
  // at this layer. The REAL D10 capture-failure guarantee is delivered by the
  // session's no-frames watchdog, covered in streaming_stt_session_test.dart
  // ("no-frames watchdog is the real D10 capture-failure detector").
}
