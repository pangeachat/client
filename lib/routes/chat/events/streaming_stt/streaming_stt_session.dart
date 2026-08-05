import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_gate.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_audio_capture.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_repo.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_state.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/wav_writer.dart';

/// The exact factory-selection [PangeaChatInputRow] uses to decide the recorder
/// path (D11). Returns a factory that builds a real [StreamingSttSession] iff
/// the flag + validated-language gate passes AND a Matrix access token is present;
/// otherwise `null`, so the recorder runs today's batch `AudioEncoder.wav` path
/// unchanged. Extracted (and unit-tested) so the gate wiring cannot silently
/// regress. Selection is pure: it never constructs the mic/socket — the closure
/// does, only when actually invoked to start a recording.
StreamingSttSession Function()? buildStreamingSessionFactory({
  required bool flagEnabled,
  required String? messageLangCodeShort,
  required String? accessToken,
  required String wsUrl,
}) {
  final applies = StreamingSttGate.applies(
    flagEnabled: flagEnabled,
    messageLangCodeShort: messageLangCodeShort,
  );
  if (!applies || accessToken == null) return null;
  // `applies` guarantees a non-null, supported language. Send the canonical
  // table key (for example, en-US -> en), never the raw regional alias.
  final lang = StreamingSttGate.canonicalShort(messageLangCodeShort)!;
  return () => StreamingSttSession(
    capture: SttAudioCapture(),
    repo: SttStreamRepo(wsUrl: wsUrl, accessToken: accessToken, lang: lang),
  );
}

/// Writes the synthesized WAV bytes to a temp file and returns its path.
/// Injected so unit tests can substitute a `dart:io`-only writer (no
/// path_provider plugin binding).
typedef WavTempFileWriter = Future<String> Function(Uint8List wav);

/// The retained-WAV + settled transcript produced when a streaming recording
/// stops (D5a). Wave 5 passes [wavPath] into `onVoiceMessageSend` (preserving
/// the existing recorded-file-path signature); wave 3 just produces it.
class StreamingSttResult {
  const StreamingSttResult({
    required this.wavPath,
    required this.transcript,
    required this.duration,
  });

  /// Temp file holding a normal, playable PCM16 WAV (see [pcm16ToWav]).
  final String wavPath;

  /// The settled final transcript (or the last partial if no final settled).
  final String transcript;

  final Duration duration;
}

/// Coordinates the streaming-STT recording lifecycle (D5a/D6/D10): one mic
/// ([SttAudioCapture]) TEED to two sinks — (a) the relay ([SttStreamRepo]) for
/// live partials and (b) an in-memory PCM16 accumulator for the retained WAV —
/// plus the RMS-derived amplitude timeline that drives today's waveform.
///
/// Transport-only and Flutter-free so it is unit-testable with fakes: the
/// [RecordingViewModelState] owns one of these when the streaming path is
/// active, and drives its callbacks into `setState`. Both collaborators are
/// injected; capture and socket are torn down on cancel/stop.
class StreamingSttSession {
  StreamingSttSession({
    required this.capture,
    required this.repo,
    WavTempFileWriter? tempFileWriter,
    this.maxDuration = const Duration(minutes: 5),
    this.finalizeTimeout = const Duration(milliseconds: 1200),
    this.connectTimeout = const Duration(seconds: 10),
    this.frameWatchdogTimeout = const Duration(seconds: 2),
    this.sampleRate = 16000,
  }) : _tempFileWriter = tempFileWriter ?? defaultWavTempFileWriter;

  final SttAudioCaptureApi capture;
  final SttStreamRepo repo;
  final WavTempFileWriter _tempFileWriter;

  /// The streaming ASR engine that produced the transcript, carried into the D9
  /// provenance so the send path records `service` on the `user_stt` embed. H9:
  /// server-authoritative — reads the provider the RELAY selected
  /// ([SttStreamRepo.selectedProvider]), with a NEUTRAL `streaming_v2` fallback
  /// until its `{"type":"provider"}` frame arrives. Never a hardcoded engine.
  String get service => repo.selectedProvider ?? 'streaming_v2';

  /// True when the relay's PRIMARY provider failed and a RUNNER-UP is serving
  /// this session (H9b `{"type":"provider","degraded":true}`); streaming
  /// stays fully live. Drives the "degraded but live" degradation banner.
  /// `false` until/unless that frame arrives. Server-authoritative, alongside
  /// [service]/[selectedProvider] — read straight from [repo].
  bool get isDegradedLive => repo.degraded;

  /// The primary provider's id when [isDegradedLive] is true (banner
  /// diagnostics); `null` on a normal (non-degraded) session.
  String? get degradedPrimaryProvider => repo.primaryProvider;

  /// Memory bound: retained PCM is capped at this duration; on overrun the
  /// session finalizes (stops the mic + socket) while preserving the capped
  /// PCM/WAV so a message can still send, and fires [onMaxDuration].
  final Duration maxDuration;

  /// Upper bound on the finalizing drain: after `stop` is sent, wait at most
  /// this long for the trailing final / speech_boundary / socket close so the
  /// settled transcript reflects the true last final (bounded — the full D7
  /// state machine is wave 4).
  final Duration finalizeTimeout;

  /// Upper bound on the connect handshake: [start] waits at most this long for
  /// the socket to reach [SttStreamState.open]. A pre-open close/error (auth,
  /// entitlement, language deny, or a transport failure) resolves it early to a
  /// DENY so the recorder falls back to the batch path (D10) rather than
  /// stranding the user in a partial-less streaming UI.
  final Duration connectTimeout;

  /// No-frames watchdog window. This is the REAL detector of a mid-stream mic
  /// failure: `record 6.1.2` re-wraps the platform stream in its own controller
  /// and forwards ONLY data — a mid-stream platform error is swallowed inside
  /// `record` and never reaches the stream we listen to, so the [capture]
  /// `onError` hook fires only when the platform actually surfaces an error
  /// (rare). To deliver the D10 "capture failure -> batch fallback" guarantee
  /// genuinely, the session treats "no PCM frame within this window" (after
  /// start, or a gap during capture) as a capture death: teardown + fall back.
  final Duration frameWatchdogTimeout;

  final int sampleRate;

  /// Retained-PCM cap in bytes (16-bit mono): the exact byte budget the tee is
  /// truncated to at [maxDuration], so neither the WS nor the buffer overruns.
  int get _maxBytes => maxDuration.inMilliseconds * sampleRate * 2 ~/ 1000;

  final BytesBuilder _pcm = BytesBuilder(copy: false);
  final List<double> _amplitudeTimeline = <double>[];

  String _liveTranscript = '';
  String _finalTranscript = '';
  List<SttWord> _finalWords = const <SttWord>[];

  // The relay emits one settled chunk (segment_final/stream_final) PER segment
  // (each endpoint/pause) and the transcript RESETS to the next chunk afterwards
  // — so the running transcript is the concatenation of ALL committed chunks plus
  // the current interim, never the latest chunk alone (which would drop everything
  // spoken before a pause). These accumulate the committed chunks + their words
  // across the whole utterance.
  final List<String> _committedSegments = <String>[];
  final List<SttWord> _committedWords = <SttWord>[];
  String _interim = '';
  bool _hasError = false;
  bool _maxReached = false;
  bool _stopped = false;
  bool _teardownDone = false;
  String? _tempPath;

  /// Set only after `_awaitOpen()==true` AND `capture.start()` succeeded (the mic
  /// is live). H8: the ONLY gate separating a POST-`ready` terminal (degrade)
  /// from a PRE-`ready` terminal (`_awaitOpen()==false` -> normal batch recorder).
  bool _openedAndMicStarted = false;

  /// Guards a `closed`-then-`error` double fire of the degrade path.
  bool _degradeStarted = false;

  /// The terminal retained-WAV result is materialized once. A transport
  /// terminal and a user stop can race, but they must share one artifact.
  Future<StreamingSttResult?>? _synthesisFuture;

  /// Capture start can outlive a cancel. Disposal waits for that start to
  /// settle, then runs exactly once so a late-started mic cannot leak.
  Future<bool>? _captureStartFuture;
  Future<void>? _captureDisposeFuture;

  Future<void>? _teardownFuture;

  /// Memoizes the single finalize run so the max-duration auto-finalize and a
  /// later [stopAndSynthesize] share one bounded drain (idempotent).
  Future<void>? _finalizeFuture;

  /// Fires if no PCM frame arrives within [frameWatchdogTimeout]; reset on every
  /// frame and cancelled on intentional stop/finalize/teardown.
  Timer? _watchdog;

  StreamSubscription<SttPartial>? _partialSub;
  StreamSubscription<SttStreamState>? _stateSub;
  StreamSubscription<void>? _providerSub;

  /// Fired whenever the live transcript or amplitude timeline changes.
  void Function()? onUpdate;

  /// Fired once when the retained buffer hits [maxDuration].
  void Function()? onMaxDuration;

  /// Fired when the capture stream itself fails at runtime — the session has
  /// already torn down; the owner should reset to today's batch path (D10).
  void Function()? onFatalError;

  /// Fired on any unexpected post-`ready` terminal: the streaming transport is
  /// gone, but the complete retained PCM is preserved and handed over for BATCH
  /// transcription (B4/KD-12). The
  /// owner sends the retained WAV via the batch path — never a stuck mic, never a
  /// discarded synth.
  void Function(StreamingSttResult retained)? onStreamDegradeToBatch;

  /// The current transcript surface: the interim partial while speaking, or the
  /// settled final after it commits. Replace-in-place — never an append log.
  String get liveTranscript => _liveTranscript;

  /// The last settled final (D7 `originalAsrText` seed for waves 4/5).
  String get finalTranscript => _finalTranscript;

  /// The per-word timings of the last settled final (D9 provenance / D8
  /// `word_timings`; align with the verbatim final only). Empty until a final
  /// settles.
  List<SttWord> get finalWords => _finalWords;

  /// The gated language the relay was opened with (the D4 `?lang=` short code,
  /// fixed at recording start). The send path stamps the streamed `lang_code`/
  /// `speaker_l2` from THIS — never from send-time settings — so a mid-flow L2
  /// change cannot mislabel (and mis-tokenize) the already-transcribed audio.
  String get lang => repo.lang;

  /// True once the relay errored (partials stop; the mic keeps buffering).
  bool get hasError => _hasError;

  bool get isMaxDurationReached => _maxReached;

  /// True from the terminal transport event until retained-WAV recovery
  /// completes. The composer disables send during this transition.
  bool get isDegradingToBatch => _degradeStarted && !_teardownDone;

  int get pcmByteLength => _pcm.length;

  /// RMS-derived amplitude values on today's `100 + 2*dBFS` scale, so the
  /// existing waveform renderer needs no change.
  List<double> get amplitudeTimeline => _amplitudeTimeline;

  int get _durationMs =>
      (_pcm.length * 1000) ~/ (sampleRate * 2); // 16-bit mono

  /// Open the socket and start the mic, teeing frames to both sinks. Returns
  /// false when permission is denied or capture fails to start — the caller
  /// then falls back to today's batch record path (D10). Never throws.
  Future<bool> start() async {
    if (!await capture.hasPermission()) return false;
    // Cancellation-safety: if teardown() ran WHILE `hasPermission()` was
    // pending, abort BEFORE connecting — otherwise we would open a socket on an
    // already-closed repo that its prior close() will never reap (leak).
    if (_teardownDone) return false;

    repo.connect();
    _partialSub = repo.partials.listen(_onPartial);
    _stateSub = repo.state.listen(_onState);
    // H9b: rebuild promptly on a provider frame (degraded-live banner) rather
    // than waiting for the next partial to happen to fire onUpdate.
    _providerSub = repo.providerUpdates.listen((_) => onUpdate?.call());

    // Commit to the streaming UI ONLY after the socket actually opens. A DENY
    // (auth/entitlement/language 1008, or a connect/transport error) surfaces
    // as a pre-open close/error -> return false -> batch fallback (D10). Without
    // this the mic would start behind a dead socket: no partials, no fallback.
    final opened = await _awaitOpen();
    // Teardown during the handshake: it already cancelled our subs + closed the
    // socket; just abort (do not start the mic).
    if (_teardownDone) return false;
    if (!opened) {
      await teardown();
      return false;
    }

    bool ok;
    try {
      final startFuture = capture.start(_onFrame, onError: _onCaptureError);
      _captureStartFuture = startFuture;
      ok = await startFuture;
    } catch (_) {
      ok = false;
    }
    // Teardown while capture.start() was in flight waits for this start and then
    // shares the exactly-once disposal below.
    if (_teardownDone) {
      await _disposeCapture();
      return false;
    }
    if (!ok) {
      await teardown();
      return false;
    }
    // H8: the mic is live AND we are past `ready` — the ONLY gate that lets a
    // later terminal state degrade to batch (a PRE-`ready` terminal never gets
    // here; it resolves _awaitOpen() false -> start() false -> batch recorder).
    _openedAndMicStarted = true;
    // The mic is live: arm the no-frames watchdog so a mic that starts but
    // delivers nothing (a mid-stream death `record` never surfaces) still
    // triggers teardown + batch fallback.
    _armWatchdog();
    return true;
  }

  /// (Re)arm the no-frames watchdog. No-op after stop/teardown.
  void _armWatchdog() {
    _watchdog?.cancel();
    if (_stopped || _teardownDone) return;
    _watchdog = Timer(frameWatchdogTimeout, _onFramesStalled);
  }

  /// The mic produced no frames within [frameWatchdogTimeout] — treat it as a
  /// capture death (D10): teardown + fall back to the batch path.
  void _onFramesStalled() {
    if (_stopped || _teardownDone) return;
    _onCaptureError(
      StateError(
        'no PCM frames within $frameWatchdogTimeout (capture stalled)',
      ),
    );
  }

  /// Resolve true once the socket reaches [SttStreamState.open]; false on the
  /// first pre-open [SttStreamState.closed]/[SttStreamState.error] or after
  /// [connectTimeout]. A separate subscription from [_stateSub].
  Future<bool> _awaitOpen() async {
    final completer = Completer<bool>();
    final sub = repo.state.listen((s) {
      if (completer.isCompleted) return;
      if (s == SttStreamState.open) {
        completer.complete(true);
      } else if (s == SttStreamState.closed || s == SttStreamState.error) {
        completer.complete(false);
      }
    });
    try {
      return await completer.future.timeout(
        connectTimeout,
        onTimeout: () => false,
      );
    } finally {
      await sub.cancel();
    }
  }

  void _onFrame(Uint8List frame) {
    if (_stopped || _maxReached) return;

    // A frame arrived: restart the no-frames watchdog (also catches a mid-stream
    // gap where frames stop without an error).
    _armWatchdog();

    // Truncate the CROSSING frame to the exact remaining byte budget BEFORE
    // teeing, so neither the WS bytes nor the retained PCM overrun the cap
    // (the crossing frame is capped, not sent/buffered whole).
    final remaining = _maxBytes - _pcm.length;
    final bool crosses = frame.length >= remaining;
    final Uint8List slice = crosses
        ? Uint8List.sublistView(frame, 0, remaining)
        : frame;

    // Sink (a): PCM16 to the relay for live partials (no-op after close).
    repo.sendAudio(slice);
    // Sink (b): accumulate the same slice for the retained WAV.
    _pcm.add(slice);
    _appendAmplitude(slice);

    if (crosses) {
      _maxReached = true;
      _watchdog?.cancel(); // intentional stop; no false capture-death fire
      onMaxDuration?.call();
      // Cap reached exactly: stop the mic AND the socket now (preserving the
      // capped buffer) so nothing is captured or sent past the limit. The user
      // can still send the capped recording.
      unawaited(_finalize());
    }
    onUpdate?.call();
  }

  /// A capture failure (D10) — from the [capture] `onError` hook IF the platform
  /// ever surfaces one, or (the real path) from the no-frames watchdog. Tears
  /// down and signals the owner to fall back to today's batch path. Never
  /// rethrows.
  void _onCaptureError(Object error) {
    _hasError = true;
    unawaited(teardown().whenComplete(() => onFatalError?.call()));
  }

  void _appendAmplitude(Uint8List frame) {
    final sampleCount = frame.length ~/ 2;
    if (sampleCount == 0) {
      _amplitudeTimeline.add(1);
      return;
    }
    final data = ByteData.view(
      frame.buffer,
      frame.offsetInBytes,
      sampleCount * 2,
    );
    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = data.getInt16(i * 2, Endian.little);
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / sampleCount);
    // dBFS relative to full-scale int16, mapped onto today's amplitude scale
    // (`100 + amplitude.current * 2`, clamped to >= 1).
    final dbfs = rms <= 0 ? -160.0 : 20 * (math.log(rms / 32768) / math.ln10);
    final value = 100 + dbfs * 2;
    _amplitudeTimeline.add(value < 1 ? 1 : value);
  }

  void _onPartial(SttPartial partial) {
    final text = partial.transcript.trim();
    if (partial.isFinal || partial.speechFinal) {
      // A committed chunk: APPEND it (never replace) so a multi-segment
      // utterance keeps every segment, then clear the interim for the next one.
      if (text.isNotEmpty) {
        _committedSegments.add(text);
        _committedWords.addAll(partial.words);
      }
      _interim = '';
    } else {
      // Interim hypothesis for the current (uncommitted) chunk: replace in place.
      _interim = text;
    }
    final segments = <String>[
      ..._committedSegments,
      if (_interim.isNotEmpty) _interim,
    ];
    // Display = all committed segments + the live interim.
    _liveTranscript = segments.join(' ');
    // Sent text = the committed segments only (the interim is not settled).
    _finalTranscript = _committedSegments.join(' ');
    _finalWords = List<SttWord>.unmodifiable(_committedWords);
    onUpdate?.call();
  }

  /// Test-only seam: apply a partial as if it arrived from the relay, so the
  /// live-transcript surface can be widget-tested without a socket.
  @visibleForTesting
  void debugApplyPartial(SttPartial partial) => _onPartial(partial);

  /// Test-only seam: buffer a PCM frame as if the mic teed it, without a real
  /// mic (exercises the post-`ready` degrade with retained audio).
  @visibleForTesting
  void debugOnFrame(Uint8List frame) => _onFrame(frame);

  /// Test-only observability: set true by any WAV synthesis
  /// ([stopAndSynthesize] or the no-drain degrade synth).
  @visibleForTesting
  bool debugSynthesizeCalled = false;

  void _onState(SttStreamState state) {
    final terminal =
        state == SttStreamState.closed || state == SttStreamState.error;
    // Any unexpected POST-`ready` terminal: the mic actually started AND we have
    // buffered audio -> degrade to batch with the retained PCM, even if partials
    // or finals already arrived, because later speech may otherwise be lost.
    // `_openedAndMicStarted` keeps a PRE-`ready` terminal OUT of
    // this branch (H8): pre-ready the mic never started, so `_awaitOpen()==false`
    // drives `start()==false` into the normal batch RECORDER (no synth, no
    // callback). `_pcm.length > 0` keeps a no-audio post-`ready` failure from
    // synthing an empty WAV.
    if (terminal &&
        _openedAndMicStarted &&
        _pcm.length > 0 &&
        !_stopped &&
        !_teardownDone) {
      unawaited(_degradeToBatch());
      return;
    }
    if (state == SttStreamState.error) {
      // Errors that cannot recover a retained WAV still surface to the owner.
      _hasError = true;
      onUpdate?.call();
    }
  }

  /// Post-`ready` terminal transport failure (B4): synthesize the retained PCM
  /// and hand it to the owner for BATCH transcription. Fires
  /// once (`_degradeStarted` guards a `closed`-then-`error` double fire).
  Future<void> _degradeToBatch() async {
    if (_teardownDone || _degradeStarted) return;
    _degradeStarted = true;
    onUpdate?.call();
    final result = await (_synthesisFuture ??= _synthesizeRetainedNoDrain());
    if (!_teardownDone && result != null) {
      onStreamDegradeToBatch?.call(result);
    }
    // Do NOT teardown here: the recorder owns the retained WAV's lifecycle (it
    // batch-transcribes then disposes the session), exactly like stop-and-send.
  }

  /// Stop capture + synthesize the retained PCM WITHOUT the finalizing drain
  /// (M12). The transport is ALREADY dead (this ran on its terminal state), so
  /// calling [stopAndSynthesize] -> `repo.stop()` + `_awaitFinalizingDrain()`
  /// would block the full [finalizeTimeout] waiting on an already-closed socket.
  /// Synthesize the retained PCM directly instead.
  Future<StreamingSttResult?> _synthesizeRetainedNoDrain() async {
    if (_teardownDone) return null;
    debugSynthesizeCalled = true;
    _stopped = true;
    _watchdog?.cancel();
    await _cancelSubs();
    await _disposeCapture();
    final pcm = _pcm.toBytes();
    if (pcm.isEmpty) {
      return null; // nothing to save (also guarded by _pcm.length>0)
    }
    final wav = pcm16ToWav(pcm, sampleRate: sampleRate);
    final path = await _tempFileWriter(wav);
    if (_teardownDone) {
      await _disposeTempArtifact(path);
      return null;
    }
    _tempPath = path; // teardown disposes it iff the recorder never sends
    final transcript = _finalTranscript.isNotEmpty
        ? _finalTranscript
        : _liveTranscript;
    return StreamingSttResult(
      wavPath: path,
      transcript: transcript,
      duration: Duration(milliseconds: _durationMs),
    );
  }

  /// Finalize (stop mic, flush socket, bounded drain, close socket) then
  /// synthesize the retained WAV to a temp file and return it with the settled
  /// transcript. Shares the one finalize run with the max-duration auto-stop.
  Future<StreamingSttResult?> stopAndSynthesize() =>
      _synthesisFuture ??= _doStopAndSynthesize();

  Future<StreamingSttResult?> _doStopAndSynthesize() async {
    if (_teardownDone) return null;
    debugSynthesizeCalled = true;
    await _finalize();
    // A teardown() (cancel/pause/dispose) may have raced the finalizing drain.
    // If it did, the buffer is already cleared and teardown owns cleanup — do
    // NOT synthesize a WAV (it would be empty and, worse, orphaned: teardown
    // ran with `_tempPath == null` so it cannot delete a file written now).
    if (_teardownDone) return null;

    final pcm = _pcm.toBytes();
    final wav = pcm16ToWav(pcm, sampleRate: sampleRate);
    final path = await _tempFileWriter(wav);
    // teardown() can also race the (async) write above — in which case it could
    // not have seen this path. Dispose it ourselves (web-aware: revoke the blob
    // / delete the file) rather than leak it.
    if (_teardownDone) {
      await _disposeTempArtifact(path);
      return null;
    }
    _tempPath = path;

    final transcript = _finalTranscript.isNotEmpty
        ? _finalTranscript
        : _liveTranscript;

    return StreamingSttResult(
      wavPath: path,
      transcript: transcript,
      duration: Duration(milliseconds: _durationMs),
    );
  }

  /// Stop the mic + flush and close the socket, preserving the retained buffer.
  /// Idempotent + memoized: the cap auto-finalize and a later stop share it.
  Future<void> _finalize() => _finalizeFuture ??= _doFinalize();

  Future<void> _doFinalize() async {
    _stopped = true;
    _watchdog?.cancel(); // intentional stop — do not fire capture-death
    await _disposeCapture();
    repo.stop(); // → relay Finalize + CloseStream (flush trailing finals)
    await _awaitFinalizingDrain();
    await _cancelSubs();
    await repo.close();
  }

  /// Bounded wait for the relay to flush ALL trailing final chunks after `stop`.
  /// Settles ONLY when the socket CLOSES/errors — by then every trailing final
  /// has arrived and accumulated via the main [_partialSub] (which stays live
  /// through the drain). Settling on the FIRST final instead would cancel the
  /// subscription before the rest of the utterance's chunks arrive and TRUNCATE
  /// the accumulated — and SENT — transcript (providers emit segment finals
  /// incrementally). Bounded by [finalizeTimeout]; proceeds regardless on timeout.
  Future<void> _awaitFinalizingDrain() async {
    final completer = Completer<void>();
    void settle() {
      if (!completer.isCompleted) completer.complete();
    }

    final drainState = repo.state.listen((s) {
      if (s == SttStreamState.closed || s == SttStreamState.error) settle();
    });

    try {
      await completer.future.timeout(finalizeTimeout, onTimeout: () {});
    } catch (_) {
    } finally {
      await drainState.cancel();
    }
  }

  /// Idempotently tear down everything (cancel/pause/navigation/dispose, D6):
  /// stop the mic, flush + close the socket, discard the retained buffer and
  /// any temp WAV. Never throws.
  Future<void> teardown() => _teardownFuture ??= _doTeardown();

  Future<void> _doTeardown() async {
    _teardownDone = true;
    _stopped = true;
    _watchdog?.cancel();
    await _cancelSubs();
    await _disposeCapture();
    repo.stop();
    await repo.close();
    // Cancellation owns the session once `_teardownDone` is set. Join any WAV
    // materialization already in flight so teardown cannot complete before its
    // callback is suppressed and its late artifact is removed.
    final synthesisFuture = _synthesisFuture;
    if (synthesisFuture != null) {
      try {
        await synthesisFuture;
      } catch (_) {}
    }
    _pcm.clear();
    _amplitudeTimeline.clear();
    if (_tempPath != null) {
      // Teardown runs AFTER a successful send has read the artifact.
      await _disposeTempArtifact(_tempPath!);
      _tempPath = null;
    }
  }

  Future<void> _disposeCapture() =>
      _captureDisposeFuture ??= _doDisposeCapture();

  Future<void> _doDisposeCapture() async {
    final startFuture = _captureStartFuture;
    if (startFuture != null) {
      try {
        await startFuture;
      } catch (_) {}
    }
    try {
      await capture.dispose();
    } catch (_) {}
  }

  /// Dispose a retained-WAV artifact, web-aware: on web it is a `blob:` object
  /// URL (revoke it — File I/O is unavailable); on native it is a temp file
  /// (delete it). Never throws. Used by both teardown and the write-race branch.
  Future<void> _disposeTempArtifact(String path) async {
    if (kIsWeb) {
      try {
        html.Url.revokeObjectUrl(path);
      } catch (_) {}
      return;
    }
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _cancelSubs() async {
    await _partialSub?.cancel();
    await _stateSub?.cancel();
    await _providerSub?.cancel();
    _partialSub = null;
    _stateSub = null;
    _providerSub = null;
  }
}

/// Default [WavTempFileWriter]: materializes the synthesized WAV to a path the
/// send boundary (`XFile(path).readAsBytes()`) can read. On native this is a
/// path_provider temp file (the same directory today's recorder uses); on WEB
/// path_provider + `dart:io File` are unavailable (they throw at runtime), so we
/// materialize a `blob:` object URL instead — exactly what the batch recorder
/// hands the send path on web. Without this, a streamed send on web throws at
/// stop and never reaches the editable/send flow.
Future<String> defaultWavTempFileWriter(Uint8List wav) async {
  if (kIsWeb) {
    final blob = html.Blob(<Uint8List>[wav], 'audio/wav');
    return html.Url.createObjectUrlFromBlob(blob);
  }
  final dir = await getTemporaryDirectory();
  final name = 'stt_stream_${DateTime.now().microsecondsSinceEpoch}.wav';
  final file = File(path_lib.join(dir.path, name));
  await file.writeAsBytes(wav);
  return file.path;
}
