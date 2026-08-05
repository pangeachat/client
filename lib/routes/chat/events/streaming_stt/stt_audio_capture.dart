import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// The mic-capture surface the streaming session depends on. Extracting it lets
/// [StreamingSttSession] be unit-tested with a fake that never constructs a real
/// [AudioRecorder] (whose constructor needs a platform binding), while
/// production uses [SttAudioCapture].
abstract interface class SttAudioCaptureApi {
  Future<bool> hasPermission();

  /// Begin streaming mic frames to [onFrame]. [onError] surfaces a runtime
  /// mic-stream failure (so the session can tear down + fall back to the batch
  /// path, D10) instead of letting it escape as an unhandled async error.
  Future<bool> start(
    void Function(Uint8List frame) onFrame, {
    void Function(Object error)? onError,
  });

  Future<void> stop();
  Future<void> dispose();
}

/// Streams PCM16 @16kHz mono mic frames for the streaming-STT pilot, reusing the
/// existing `record` package (no new dependency). The relay expects raw PCM16 at
/// 16kHz (`encoding=linear16&sample_rate=16000`), so we request exactly that and
/// forward each frame untouched to the transport.
///
/// Lifted from Luna's `LunaAudioCapture` (transport-only, zero UI / lib-pages
/// coupling) and renamed; the config and re-entrancy guard are unchanged.
class SttAudioCapture implements SttAudioCaptureApi {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  bool _running = false;
  bool _starting = false;

  bool get isRunning => _running;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Begin streaming mic frames to [onFrame]. Returns false if mic permission is
  /// denied. Echo-cancel + noise-suppress on, matching the existing recorder
  /// config. Guarded against re-entrancy so a rapid mic toggle cannot
  /// double-start.
  @override
  Future<bool> start(
    void Function(Uint8List frame) onFrame, {
    void Function(Object error)? onError,
  }) async {
    if (_running || _starting) return _running;
    _starting = true;
    try {
      if (!await _recorder.hasPermission()) return false;
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _running = true;
      // [onError] forwards a capture-stream error IF one is surfaced — but note
      // `record 6.1.2` re-wraps the platform stream and forwards DATA ONLY, so a
      // mid-stream platform error is swallowed inside `record` and usually never
      // reaches here. The session's no-frames watchdog is the real detector of a
      // mid-stream mic death (D10); this hook only catches the rare surfaced one.
      _sub = stream.listen(onFrame, onError: onError);
      return true;
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
    _sub = null;
    await _recorder.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
