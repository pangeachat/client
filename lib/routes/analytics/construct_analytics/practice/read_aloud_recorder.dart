import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_match.dart';
import 'package:fluffychat/routes/chat/audio_player.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_audio_capture.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/wav_writer.dart';

enum ReadAloudPhase {
  idle,
  recording,

  /// The mic has stopped and the words are settling, or the recording is
  /// being transcribed.
  finalizing,

  /// A take finished; [ReadAloudRecorder.heard] and [ReadAloudRecorder.lastTake]
  /// describe it.
  done,

  /// No route could transcribe the recording. Never recorded as a miss and
  /// never costs a try: the learner retries or skips.
  failed,

  /// The microphone was refused or is absent.
  micUnavailable,
}

/// What one recording produced.
class ReadAloudTake {
  const ReadAloudTake({
    required this.transcript,
    required this.wav,
    required this.duration,
    required this.waveform,
  });

  final String transcript;
  final Uint8List? wav;
  final Duration duration;
  final List<int>? waveform;
}

/// Transcribe a WAV through the batch route. Returns the words heard (empty
/// when the audio held none), or null when no route could transcribe it.
typedef ReadAloudTranscribe = Future<List<String>?> Function(Uint8List wav);

/// One read-aloud item's microphone: records the learner reading [reference]
/// and says which of its words were heard. Live through the streaming relay
/// where the target language is routed for streaming, so the words settle as
/// they are spoken; otherwise through the batch route, so they fill in together
/// after the recording ends (practice-exercises.instructions.md, "Speaking
/// practice"). Transport-only and widget-free, so it is unit-tested with the
/// streaming session's fakes.
class ReadAloudRecorder extends ChangeNotifier {
  ReadAloudRecorder({
    required this.reference,
    required Future<bool> Function() hasMicPermission,
    required StreamingSttSession Function()? streamingSessionFactory,
    required SttAudioCaptureApi Function() captureFactory,
    required ReadAloudTranscribe transcribe,
    this.maxTries = 3,
  }) : _hasMicPermission = hasMicPermission,
       _streamingSessionFactory = streamingSessionFactory,
       _captureFactory = captureFactory,
       _transcribe = transcribe,
       heard = List<bool>.filled(reference.length, false);

  /// The words the learner reads, in order, as they appear in the sentence.
  final List<String> reference;
  final int maxTries;
  final Future<bool> Function() _hasMicPermission;
  final StreamingSttSession Function()? _streamingSessionFactory;
  final SttAudioCaptureApi Function() _captureFactory;
  final ReadAloudTranscribe _transcribe;

  ReadAloudPhase phase = ReadAloudPhase.idle;

  /// Per word of [reference], whether it has been heard: live while a
  /// streaming recording runs, settled once the take is done.
  List<bool> heard;

  /// The transcript as it settles while a streaming recording runs, shown
  /// under the sentence the way the voice-message recorder shows its live
  /// line; the settled transcript once the take is done. Empty on the batch
  /// route until the take ends.
  String liveTranscript = '';
  ReadAloudTake? lastTake;
  int triesUsed = 0;

  int get triesLeft => maxTries - triesUsed;
  bool get allHeard => heard.every((h) => h);
  int get unheardCount => heard.where((h) => !h).length;

  StreamingSttSession? _session;
  SttAudioCaptureApi? _capture;
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  bool _disposed = false;

  /// Bumped by [start] and [cancel], so a start, stop or relay callback still
  /// in flight when the take was discarded cannot touch the next one.
  int _generation = 0;

  bool _stale(int generation) => _disposed || generation != _generation;

  Future<void> start() async {
    if (phase == ReadAloudPhase.recording ||
        phase == ReadAloudPhase.finalizing) {
      return;
    }
    final generation = ++_generation;
    heard = List<bool>.filled(reference.length, false);
    liveTranscript = '';
    lastTake = null;
    phase = ReadAloudPhase.recording;
    notifyListeners();

    if (!await _hasMicPermission()) {
      if (!_stale(generation)) _setPhase(ReadAloudPhase.micUnavailable);
      return;
    }
    if (_stale(generation)) return;

    final factory = _streamingSessionFactory;
    if (factory != null) {
      final session = factory();
      session.onUpdate = () {
        if (!_stale(generation)) _onLive(session.liveTranscript);
      };
      session.onMaxDuration = () {
        if (!_stale(generation)) unawaited(stop());
      };
      session.onFatalError = () {
        if (!_stale(generation)) _setPhase(ReadAloudPhase.failed);
      };
      // The relay died after the mic was live: the session has stopped the
      // mic and kept the audio, so the batch route judges this take.
      session.onStreamDegradeToBatch = (retained) {
        if (_stale(generation)) return;
        unawaited(
          _finishFromBatch(
            session.lastWav,
            retained.duration,
            session.amplitudeTimeline,
            generation,
          ),
        );
      };
      bool opened;
      try {
        opened = await session.start();
      } catch (_) {
        opened = false;
      }
      if (_stale(generation)) {
        await session.teardown();
        return;
      }
      if (opened) {
        _session = session;
        return;
      }
      // Not routed for streaming, or the relay refused: record for the batch
      // route instead.
      await session.teardown();
    }

    final capture = _captureFactory();
    bool ok;
    try {
      ok = await capture.start(
        _pcm.add,
        onError: (_) => _setPhase(ReadAloudPhase.failed),
      );
    } catch (_) {
      ok = false;
    }
    if (_stale(generation)) {
      await capture.dispose();
      return;
    }
    if (!ok) {
      await capture.dispose();
      _setPhase(ReadAloudPhase.micUnavailable);
      return;
    }
    _capture = capture;
  }

  /// Discard the recording in progress without judging it or spending a
  /// take: the mic closes, the words reset, and the item is idle again.
  Future<void> cancel() async {
    if (phase != ReadAloudPhase.recording) return;
    _generation++;
    final session = _session;
    _session = null;
    final capture = _capture;
    _capture = null;
    _pcm.clear();
    heard = List<bool>.filled(reference.length, false);
    liveTranscript = '';
    _setPhase(ReadAloudPhase.idle);
    if (session != null) await session.teardown();
    if (capture != null) await capture.dispose();
  }

  /// Start over: discard the recording in progress and begin a fresh one.
  Future<void> restart() async {
    await cancel();
    if (_disposed) return;
    await start();
  }

  /// End the take. The streaming path judges the settled final; the batch
  /// path sends the WAV for transcription first.
  Future<void> stop() async {
    if (phase != ReadAloudPhase.recording) return;
    final generation = _generation;
    phase = ReadAloudPhase.finalizing;
    notifyListeners();

    final session = _session;
    if (session != null) {
      _session = null;
      final result = await session.stopAndSynthesize();
      final wav = session.lastWav;
      final amplitudes = List<double>.from(session.amplitudeTimeline);
      await session.teardown();
      if (_stale(generation)) return;
      if (result == null) {
        _setPhase(ReadAloudPhase.failed);
        return;
      }
      _finish(
        spokenWords(result.transcript),
        result.transcript,
        wav,
        result.duration,
        _waveformFromAmplitudes(amplitudes),
      );
      return;
    }

    final capture = _capture;
    _capture = null;
    if (capture == null) {
      _setPhase(ReadAloudPhase.failed);
      return;
    }
    await capture.stop();
    await capture.dispose();
    if (_stale(generation)) return;
    final wav = pcm16ToWav(_pcm.takeBytes());
    // PCM16 mono at 16 kHz is 32 bytes per millisecond.
    final duration = Duration(milliseconds: (wav.length - 44) ~/ 32);
    await _finishFromBatch(wav, duration, const <double>[], generation);
  }

  Future<void> _finishFromBatch(
    Uint8List? wav,
    Duration duration,
    List<double> amplitudes,
    int generation,
  ) async {
    if (wav == null) {
      _setPhase(ReadAloudPhase.failed);
      return;
    }
    final words = await _transcribe(wav);
    if (_stale(generation)) return;
    if (words == null) {
      _setPhase(ReadAloudPhase.failed);
      return;
    }
    _finish(
      words,
      words.join(' '),
      wav,
      duration,
      _waveformFromAmplitudes(amplitudes),
    );
  }

  void _finish(
    List<String> words,
    String transcript,
    Uint8List? wav,
    Duration duration,
    List<int>? waveform,
  ) {
    heard = readAloudHeard(reference, words);
    liveTranscript = transcript;
    lastTake = ReadAloudTake(
      transcript: transcript,
      wav: wav,
      duration: duration,
      waveform: waveform,
    );
    triesUsed++;
    _setPhase(ReadAloudPhase.done);
  }

  void _onLive(String transcript) {
    if (phase != ReadAloudPhase.recording) return;
    liveTranscript = transcript;
    heard = readAloudHeard(reference, spokenWords(transcript));
    notifyListeners();
    // Every word settled: the take is complete without a second tap.
    if (allHeard) unawaited(stop());
  }

  void _setPhase(ReadAloudPhase next) {
    if (_disposed) return;
    phase = next;
    notifyListeners();
  }

  List<int>? _waveformFromAmplitudes(List<double> amps) {
    if (amps.isEmpty) return null;
    const waveCount = AudioPlayerWidget.wavesCount;
    final step = amps.length < waveCount
        ? 1
        : (amps.length / waveCount).round();
    return [
      for (var i = 0; i < amps.length; i += step)
        (amps[i] / 100 * 1024).round(),
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.teardown());
    final capture = _capture;
    _capture = null;
    if (capture != null) unawaited(capture.dispose());
    super.dispose();
  }
}
