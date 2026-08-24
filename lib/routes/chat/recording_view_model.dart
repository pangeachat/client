import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/degradation_banner.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/editable_transcript.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_provenance.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'audio_player.dart';

// #Pangea
class PermissionException implements Exception {}

class EmptyAudioException implements Exception {}
// Pangea#

// #Pangea
/// Outcome of a flag-gated streaming start attempt (see `_startStreaming`).
enum _StreamStartOutcome {
  /// Streaming is live.
  started,

  /// A genuine unavailability — fall back to the batch recorder (D10).
  failed,

  /// A cancel/dispose raced the async start — do not touch state or start a
  /// recorder.
  aborted,
}

/// The voice-send callback (`ChatController.onVoiceMessageSend`). The optional
/// [streamedTranscript] carries the D8/D9 streamed provenance on the editable
/// path; omitting it (the batch path) keeps today's exact send behaviour.
typedef VoiceMessageSend =
    Future<void> Function(
      String path,
      int duration,
      List<int> waveform,
      String? fileName, {
      StreamingSttSendData? streamedTranscript,
    });
// Pangea#

class RecordingViewModel extends StatefulWidget {
  final Widget Function(BuildContext, RecordingViewModelState) builder;

  // #Pangea
  /// Builds a fresh streaming-STT session when the live-streaming path applies
  /// (flag ON + English, per [StreamingSttGate]). `null` keeps today's batch
  /// `AudioEncoder.wav` recorder path byte-for-byte. Injected as a factory so
  /// the recorder stays widget-test-friendly and the caller owns the token/URL.
  final StreamingSttSession Function()? streamingSessionFactory;

  /// True when the streaming flag is ON but [StreamingSttGate] rejected the
  /// CURRENT message language specifically — never a flag-off or
  /// missing-token reason (those leave [streamingSessionFactory] null too,
  /// but silently: the pilot simply is not part of this build/session).
  /// Computed by the caller from `StreamingSttGate.applies` so the gate stays
  /// the single source of truth for language routing. Drives the
  /// LANGUAGE-UNSUPPORTED degradation banner, snapshotted at
  /// [RecordingViewModelState.startRecording] (never re-read mid-recording —
  /// same "fixed at recording start" principle as [StreamingSttSession.lang]).
  final bool languageUnsupportedForStreaming;
  // Pangea#

  const RecordingViewModel({
    required this.builder,
    // #Pangea
    this.streamingSessionFactory,
    this.languageUnsupportedForStreaming = false,
    // Pangea#
    super.key,
  });

  @override
  RecordingViewModelState createState() => RecordingViewModelState();
}

class RecordingViewModelState extends State<RecordingViewModel> {
  Timer? _recorderSubscription;
  Duration duration = Duration.zero;

  bool isSending = false;

  // #Pangea
  /// Whether a voice recording is in progress. Mirrors [isRecording], but
  /// readable without a reference to this widget so [ChatController.isSuppressed]
  /// can silence automatic read-aloud while the mic is hot: recording is inline
  /// rather than modal, so device TTS would otherwise play out loud, be captured
  /// by the recorder, and get uploaded to speech-to-text.
  static bool isRecordingAnywhere = false;

  // bool get isRecording => _audioRecorder != null;
  bool get isRecording => _audioRecorder != null || _streaming != null;
  // Pangea#

  AudioRecorder? _audioRecorder;
  final List<double> amplitudeTimeline = [];

  String? fileName;

  bool isPaused = false;

  // #Pangea
  /// Monotonic token for an in-flight [startRecording] attempt. cancel/dispose
  /// bump it; an async start whose token has changed was aborted by the user and
  /// MUST NOT fall through to the batch recorder or `setState` after dispose.
  int _startGeneration = 0;

  /// The active streaming-STT session (D5a/D6), or `null` on today's batch
  /// path. Non-null iff the streaming capture path is running.
  StreamingSttSession? _streaming;

  /// True while the flag-gated streaming capture path is active. Drives the
  /// live-transcript surface + PCM-derived waveform in [RecordingInputRow].
  bool get isStreaming => _streaming != null;

  /// The D7 editable-transcript buffer, non-null once the streaming recording
  /// has stopped and the settled final became editable (D7 `editableClean`). On
  /// the recording/batch path this is `null`.
  EditableTranscript? _editable;

  /// True across the async `finalizing → editableClean` transition in
  /// [stopStreamingToEditable] (mic stop + bounded drain + WAV synth). A guard
  /// against a double-tap re-entering the stop before `_editable` is set: a
  /// second call would otherwise pass the `_editable == null` check during the
  /// await, run a concurrent `stopAndSynthesize`, and overwrite `_editable`,
  /// leaking the first controller + listener. Also drives the row to disable
  /// the stop control while finalizing.
  bool _finalizingToEditable = false;

  /// The retained WAV + duration synthesized at stop, held until the edited
  /// transcript is sent (wave 5 threads the transcript; wave 4 sends the WAV).
  StreamingSttResult? _pendingResult;

  /// Precomputed waveform bars from the stop-time amplitude timeline (the
  /// session is torn down on send/cancel, so capture them at stop).
  List<int>? _pendingWaveform;

  /// True once an unexpected post-`ready` terminal degraded the streaming session
  /// to batch (B4): [_pendingResult]/[_pendingWaveform] hold the retained WAV +
  /// waveform, and [stopAndSend] routes them through the BATCH send path
  /// (`streamedTranscript` omitted -> the server transcribes the WAV).
  bool _degradedToBatch = false;

  /// Snapshot of [RecordingViewModel.languageUnsupportedForStreaming] taken at
  /// [startRecording] (D11 — fixed for the whole recording, never re-read from
  /// a later, possibly-changed L2 setting).
  bool _languageUnsupported = false;

  /// The degradation reason last DISMISSED by the user (the banner's X), or
  /// `null` if nothing has been dismissed this recording. Tracked BY KIND —
  /// not a blanket flag — so a later, DIFFERENT (worse) degradation always
  /// resurfaces even though an earlier, milder one was dismissed.
  DegradationBannerKind? _dismissedBannerKind;

  /// The degradation reason to surface in the banner mounted above the voice
  /// input row's controls, or [DegradationBannerKind.none] when nothing has
  /// degraded (or the current reason was already dismissed this recording).
  DegradationBannerKind get degradationBanner {
    final kind = _currentDegradationKind;
    return kind == _dismissedBannerKind ? DegradationBannerKind.none : kind;
  }

  /// Computed fresh from live state on every read (never cached): a
  /// terminal batch-degrade (B4, streaming is GONE) outranks a live-degrade
  /// (H9b, streaming continues) outranks the client-local language gate
  /// (D11), so a worsening mid-recording condition is never masked by an
  /// earlier, milder one.
  DegradationBannerKind get _currentDegradationKind {
    if (_degradedToBatch || _streaming?.isDegradingToBatch == true) {
      return DegradationBannerKind.degradedToBatch;
    }
    if (_streaming?.isDegradedLive == true) {
      return DegradationBannerKind.degradedLive;
    }
    if (_languageUnsupported) return DegradationBannerKind.languageUnsupported;
    return DegradationBannerKind.none;
  }

  /// Dismiss the CURRENTLY shown banner (the row's X control). Hides only
  /// this reason for the rest of the recording — a later, different reason
  /// still surfaces (see [degradationBanner]).
  void dismissDegradationBanner() {
    setState(() => _dismissedBannerKind = _currentDegradationKind);
  }

  /// True once the streaming recording has stopped and the transcript is
  /// editable (D7 `editableClean`/`editableDirty`). Drives the swap from the
  /// read-only live line to the editable `TextField` in [RecordingInputRow].
  bool get isEditingTranscript => _editable != null;

  /// True while the async `finalizing → editableClean` transition is in flight
  /// (the row disables the stop control so a double-tap cannot re-enter it).
  bool get isFinalizingToEditable =>
      _finalizingToEditable ||
      (_streaming?.isDegradingToBatch == true && _pendingResult == null);

  /// Whether the live-stream button should enter transcript editing. A terminal
  /// recovery owns the same button and must complete into the batch-send path.
  bool get shouldStopStreamingToEditable =>
      _streaming != null &&
      _editable == null &&
      !_degradedToBatch &&
      _streaming?.isDegradingToBatch != true;

  /// The editable buffer's controller for the `TextField`, or `null` off the
  /// editable path.
  EditableTranscriptController? get editableController => _editable?.controller;

  /// The D9 provenance snapshot for the send path (wave 5). `null` unless a
  /// streamed transcript is being edited.
  StreamingSttSendData? get streamingSendData => _editable?.buildSendData();

  /// Test-only view of the D7 buffer state (or `null` off the editable path).
  @visibleForTesting
  EditableTranscriptState? get editableTranscriptStateForTest =>
      _editable?.state;

  /// Test-only handle to the D7 buffer (or `null` off the editable path) so a
  /// send-outcome test can hold the reference across teardown and assert its
  /// terminal state.
  @visibleForTesting
  EditableTranscript? get editableTranscriptForTest => _editable;

  /// The settling live transcript (replace-in-place; empty on the batch path).
  String get liveTranscript => _streaming?.liveTranscript ?? '';

  /// Waveform source: the streaming session's RMS timeline when streaming, else
  /// today's amplitude timeline — so the row renderer needs no branch.
  List<double> get waveformAmplitudes =>
      _streaming?.amplitudeTimeline ?? amplitudeTimeline;
  // Pangea#

  Future<void> startRecording(Room room) async {
    // #Pangea
    // Claim this attempt's generation; a cancel/dispose during any await below
    // bumps it, letting us abort instead of starting a recorder after teardown.
    final int gen = ++_startGeneration;
    // D11: snapshot the gate's language-routing decision NOW — fixed for the
    // whole recording, exactly like the streamed session's own `lang`.
    _languageUnsupported = widget.languageUnsupportedForStreaming;
    _dismissedBannerKind = null;
    // Pangea#
    room.client.getConfig(); // Preload server file configuration.
    if (PlatformInfos.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt < 19) {
        showOkAlertDialog(
          context: context,
          title: L10n.of(context).unsupportedAndroidVersion,
          message: L10n.of(context).unsupportedAndroidVersionLong,
          okLabel: L10n.of(context).close,
        );
        return;
      }
    }
    // #Pangea
    // if (await AudioRecorder().hasPermission() == false) return;
    try {
      if (await AudioRecorder().hasPermission() == false) {
        showOkAlertDialog(
          context: context,
          title: L10n.of(context).oopsSomethingWentWrong,
          message: L10n.of(context).emptyAudioError,
        );
        return;
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: "Error while checking audio recording permission: ${e.toString()}",
        s: s,
        data: {},
      );
      showOkAlertDialog(
        context: context,
        title: L10n.of(context).oopsSomethingWentWrong,
        message: L10n.of(context).emptyAudioError,
      );
      return;
    }
    // Pangea#

    // #Pangea
    // Streaming capture path (D5a/D6): flag ON + English. On a genuine
    // unavailability (permission/connect/capture failure) fall through to
    // today's batch recorder (D10). But if the attempt was ABORTED by
    // cancel/dispose, stop here — do NOT start a recorder after teardown.
    if (widget.streamingSessionFactory != null) {
      final outcome = await _startStreaming(gen);
      if (outcome != _StreamStartOutcome.failed) {
        // On a live streaming start the mic is hot, so mark recording-anywhere
        // for parity with the batch path below: main's read-aloud suppression
        // (ChatController.isSuppressed) reads this static flag to silence device
        // TTS that would otherwise play out loud, be captured by the recorder,
        // and get uploaded to speech-to-text. `aborted` means the capture was
        // torn down (its cancel/dispose ran _reset), so only flag `started`.
        // _reset() clears it when the streaming session ends.
        if (outcome == _StreamStartOutcome.started) isRecordingAnywhere = true;
        return;
      }
    }
    // Aborted (cancel/dispose) before reaching the batch recorder, or the
    // widget is gone: never start a recorder / setState after teardown.
    if (!mounted || _startGeneration != gen) return;
    // Pangea#

    final audioRecorder = _audioRecorder ??= AudioRecorder();
    // #Pangea
    isRecordingAnywhere = true;
    // Pangea#
    setState(() {});

    try {
      // #Pangea
      // final codec = kIsWeb
      //     // Web seems to create webm instead of ogg when using opus encoder
      //     // which does not play on iOS right now. So we use wav for now:
      //     ? AudioEncoder.wav
      //     // Everywhere else we use opus if supported by the platform:
      //     : !PlatformInfos
      //               .isIOS && // Blocked by https://github.com/llfbandit/record/issues/560
      //           await audioRecorder.isEncoderSupported(AudioEncoder.opus)
      //     ? AudioEncoder.opus
      //     : AudioEncoder.aacLc;
      const codec = AudioEncoder.wav;
      // Pangea#
      fileName =
          'recording${DateTime.now().microsecondsSinceEpoch}.${codec.fileExtension}';
      String? path;
      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        path = path_lib.join(tempDir.path, fileName);
      }

      final result = await audioRecorder.hasPermission();
      if (result != true) {
        showOkAlertDialog(
          context: context,
          title: L10n.of(context).oopsSomethingWentWrong,
          message: L10n.of(context).noPermission,
        );
        return;
      }
      await WakelockPlus.enable();

      await audioRecorder.start(
        RecordConfig(
          bitRate: AppSettings.audioRecordingBitRate.value,
          sampleRate: AppSettings.audioRecordingSamplingRate.value,
          numChannels: AppSettings.audioRecordingNumChannels.value,
          autoGain: AppSettings.audioRecordingAutoGain.value,
          echoCancel: AppSettings.audioRecordingEchoCancel.value,
          noiseSuppress: AppSettings.audioRecordingNoiseSuppress.value,
          encoder: codec,
        ),
        path: path ?? '',
      );
      setState(() => duration = Duration.zero);
      _subscribe();
    } catch (e, s) {
      Logs().w('Unable to start voice message recording', e, s);
      showOkAlertDialog(
        context: context,
        title: L10n.of(context).oopsSomethingWentWrong,
        message: e.toString(),
      );
      setState(_reset);
    }
  }

  @override
  void dispose() {
    // #Pangea
    // Invalidate any in-flight streaming start so it aborts instead of starting
    // a recorder / setState after dispose.
    _startGeneration++;
    // Pangea#
    _reset();
    super.dispose();
  }

  void _subscribe() {
    _recorderSubscription?.cancel();
    _recorderSubscription = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      final amplitude = await _audioRecorder!.getAmplitude();
      var value = 100 + amplitude.current * 2;
      value = value < 1 ? 1 : value;
      amplitudeTimeline.add(value);
      setState(() {
        duration += const Duration(milliseconds: 100);
      });
    });
  }

  // #Pangea
  /// Start the flag-gated streaming capture path (D5a). Returns:
  /// - [_StreamStartOutcome.started] when streaming is live;
  /// - [_StreamStartOutcome.failed] on a genuine unavailability (so
  ///   [startRecording] falls back to the batch recorder, D10);
  /// - [_StreamStartOutcome.aborted] when a cancel/dispose ([gen] changed or the
  ///   widget unmounted) raced this async start — the caller must NOT fall back
  ///   to batch or `setState` after teardown.
  Future<_StreamStartOutcome> _startStreaming(int gen) async {
    final session = widget.streamingSessionFactory!.call();
    if (!mounted || _startGeneration != gen) {
      await session.teardown();
      return _StreamStartOutcome.aborted;
    }
    _streaming = session;
    _wireStreamingCallbacks(session);

    bool started;
    try {
      started = await session.start();
    } catch (_) {
      started = false;
    }
    // Aborted by cancel/dispose while start() was pending: tear the session down
    // (idempotent) and abort — do not touch state or fall back to batch.
    if (!mounted || _startGeneration != gen) {
      await session.teardown();
      if (identical(_streaming, session)) _streaming = null;
      return _StreamStartOutcome.aborted;
    }
    if (!started) {
      await session.teardown();
      if (identical(_streaming, session)) _streaming = null;
      return _StreamStartOutcome.failed;
    }

    try {
      await WakelockPlus.enable();
    } catch (_) {
      await session.teardown();
      if (identical(_streaming, session)) _streaming = null;
      return _StreamStartOutcome.failed;
    }
    if (!mounted || _startGeneration != gen) {
      await session.teardown();
      if (identical(_streaming, session)) _streaming = null;
      return _StreamStartOutcome.aborted;
    }
    setState(() => duration = Duration.zero);
    _subscribeStreaming();
    return _StreamStartOutcome.started;
  }

  void _wireStreamingCallbacks(StreamingSttSession session) {
    session.onUpdate = () {
      if (mounted) setState(() {});
    };
    // On the max-duration cap, freeze the clock: the session has already
    // finalized (stopped mic + socket) while keeping the capped buffer, so the
    // user can still send.
    session.onMaxDuration = () {
      _recorderSubscription?.cancel();
      if (mounted) setState(() {});
    };
    // A runtime capture failure has already torn the session down inside the
    // session; reset the recorder so the user re-records via today's batch
    // path (D10). Never leaves a dangling mic/socket.
    session.onFatalError = () {
      if (mounted) cancel();
    };
    // An unexpected post-`ready` terminal (B4): capture the complete retained
    // WAV + waveform and mark the recorder batch-ready. Do NOT null
    // _streaming (B5 — that would skip its teardown/temp-artifact cleanup) and do
    // NOT invent a transcribe seam — the batch send is the EXISTING stopAndSend
    // path with streamedTranscript omitted. The session already stopped the mic.
    session.onStreamDegradeToBatch = (retained) {
      if (!mounted) return;
      _pendingResult = retained;
      _pendingWaveform = _waveformFromAmplitudes(
        _streaming?.amplitudeTimeline ?? const <double>[],
      );
      _degradedToBatch = true;
      setState(() {});
    };
  }

  /// Test-only seam: attach an already-started [StreamingSttSession] (built with
  /// fakes) so the streaming lifecycle can be widget-tested without the mic /
  /// wakelock / path_provider platform plugins that [_startStreaming] touches.
  /// Mirrors the production effect of a successful ([_StreamStartOutcome.started])
  /// streaming start, including marking [isRecordingAnywhere] so tests observe
  /// the same read-aloud-suppression state a live stream produces.
  @visibleForTesting
  void debugAttachStreamingSession(StreamingSttSession session) {
    _streaming = session;
    isRecordingAnywhere = true;
    _wireStreamingCallbacks(session);
    _subscribeStreaming();
  }

  /// Test-only seam: enter the D7 editable state directly with a settled
  /// [transcript] (+ optional [words]/[service]/[result]/[waveform]) so the
  /// editable-field-replaces-live-line + user-edit lifecycle can be
  /// widget-tested without driving the real mic-stop / WAV-synthesis path
  /// (path_provider) or the bounded finalizing drain's real-clock timing.
  @visibleForTesting
  void debugEnterEditable(
    String transcript, {
    List<SttWord> words = const <SttWord>[],
    String service = 'deepgram',
    StreamingSttResult? result,
    List<int>? waveform,
  }) {
    _recorderSubscription?.cancel();
    _pendingResult =
        result ??
        StreamingSttResult(
          wavPath: '',
          transcript: transcript,
          duration: Duration.zero,
        );
    _pendingWaveform = waveform ?? const <int>[];
    // Same empty-stream guard as the real settle path: an empty transcript routes to batch.
    if (_routeEmptyStreamToBatch(_pendingResult!)) {
      setState(() {});
      return;
    }
    _editable = EditableTranscript(
      originalAsrText: transcript,
      words: words,
      service: service,
      onInvalidateTranslationCache: _invalidateTranscriptTranslationCache,
    );
    _editable!.controller.addListener(_onEditableChanged);
    setState(() {});
  }

  /// Duration clock for the streaming path. The waveform/partials repaint on the
  /// session's own frame/partial callbacks; this only advances the timer text.
  void _subscribeStreaming() {
    _recorderSubscription?.cancel();
    _recorderSubscription = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) {
      if (_streaming?.isMaxDurationReached ?? true) {
        _recorderSubscription?.cancel();
        return;
      }
      setState(() {
        duration += const Duration(milliseconds: 100);
      });
    });
  }

  /// Stop the streaming capture, synthesize the retained WAV, and hand its path
  /// to [onSend] via the SAME `(path, duration, waveform, fileName)` signature
  /// the batch path uses (D5a). Wave 5 threads the settled transcript through
  /// this call; wave 3 sends the WAV exactly like today.
  Future<void> _stopStreamingAndSend(VoiceMessageSend onSend) async {
    _recorderSubscription?.cancel();
    final session = _streaming;
    if (session == null) return;

    final result = await session.stopAndSynthesize();
    if (result == null) {
      cancel();
      return;
    }

    final amps = session.amplitudeTimeline;
    const waveCount = AudioPlayerWidget.wavesCount;
    final step = amps.length < waveCount
        ? 1
        : (amps.length / waveCount).round();
    final waveform = <int>[];
    for (var i = 0; i < amps.length; i += step) {
      waveform.add((amps[i] / 100 * 1024).round());
    }

    if (amps.isEmpty || amps.every((e) => e <= 1)) {
      if (mounted) {
        showOkAlertDialog(
          context: context,
          title: L10n.of(context).oopsSomethingWentWrong,
          message: EmptyAudioException().toLocalizedString(context),
        );
      }
      cancel();
      return;
    }

    // Direct send (no editable review): embed the settled streaming transcript
    // VERBATIM (isEdited=false) so the send skips re-transcribing the WAV and
    // carries the streamed provenance, exactly like the editable path.
    final streamedTranscript = StreamingSttSendData(
      text: result.transcript,
      originalAsrText: result.transcript,
      isEdited: false,
      editDistance: 0,
      words: session.finalWords,
      service: session.service,
      langCode: session.lang,
    );

    setState(() => isSending = true);
    try {
      await onSend(
        result.wavPath,
        result.duration.inMilliseconds,
        waveform,
        path_lib.basename(result.wavPath),
        streamedTranscript: streamedTranscript,
      );
    } catch (e, s) {
      Logs().e('Unable to send streaming voice message', e, s);
      setState(() => isSending = false);
      return;
    }

    cancel();
  }

  /// Downsample an amplitude timeline to the fixed waveform-bar count the
  /// player renders (the same reduction both send paths use).
  List<int> _waveformFromAmplitudes(List<double> amps) {
    const waveCount = AudioPlayerWidget.wavesCount;
    final step = amps.length < waveCount
        ? 1
        : (amps.length / waveCount).round();
    final waveform = <int>[];
    for (var i = 0; i < amps.length; i += step) {
      waveform.add((amps[i] / 100 * 1024).round());
    }
    return waveform;
  }

  /// D7 `finalizing → editableClean`: stop the mic + run the bounded finalizing
  /// drain (wave 3), synthesize the retained WAV, then hand the settled final to
  /// a fresh [EditableTranscript] and swap the read-only live line for the
  /// editable `TextField`. The WAV + waveform are held ([_pendingResult]/
  /// [_pendingWaveform]) so a later edit-then-send reuses them without
  /// re-transcribing. Send wiring itself is wave 5 ([sendEditedTranscript]).
  ///
  /// EMPTY-STREAM GUARD (D10): a provider that connected and streamed but produced NO usable
  /// transcript (e.g. Soniox returns empty on ~1/10 German clips — the owner-override route) must
  /// NOT settle into an empty editable base, which is strictly worse than today's batch. Route the
  /// retained WAV through the BATCH path exactly like a terminal degrade: [_degradedToBatch] omits
  /// the streamed provenance so the server transcribes the WAV via the multi-provider batch chain,
  /// and the degraded-to-batch banner tells the user. Shared by the real settle
  /// ([stopStreamingToEditable]) and the [debugEnterEditable] test seam so both take the identical
  /// decision. Returns true when it took the batch route (the caller must create NO editable).
  bool _routeEmptyStreamToBatch(StreamingSttResult result) {
    if (result.transcript.trim().isNotEmpty) return false;
    _degradedToBatch = true;
    return true;
  }

  /// LATE-FINAL SAFETY (D7, impossible-by-construction): [StreamingSttSession.
  /// stopAndSynthesize] runs the bounded finalizing drain (during which the
  /// session's OWN partial subscription still updates its `finalTranscript`) and
  /// THEN cancels every session subscription and closes the socket BEFORE it
  /// returns. The [EditableTranscript] is created here, AFTER that, seeded with
  /// the fully-settled final — and it is NEVER wired to the session's partial
  /// stream. So no partial/final can reach the editable buffer once editing has
  /// begun: a late final cannot clobber a user edit because none can arrive at
  /// all. [EditableTranscript.applyStreamingUpdate]'s discard rule is the
  /// buffer-level contract + defense-in-depth if that wiring ever changes; the
  /// VM relies on the subscription lifecycle, not on calling it. (Covered by the
  /// "no partial reaches the editable buffer after stop" integration test.)
  Future<void> stopStreamingToEditable(VoiceMessageSend onSend) async {
    final session = _streaming;
    // The `_finalizingToEditable` guard closes the double-tap window: the
    // `_editable == null` check alone is not enough because `_editable` stays
    // null across the `stopAndSynthesize` await below.
    if (session == null || _editable != null || _finalizingToEditable) return;
    // Snapshot the generation so a cancel/pause/dispose/new-start that races the
    // drain (each bumps `_startGeneration` and nulls `_streaming`) invalidates
    // this continuation — otherwise a cancelled session could reappear as an
    // editable buffer or fire an empty-audio dialog after teardown.
    final gen = _startGeneration;
    _finalizingToEditable = true;
    setState(() {});
    _recorderSubscription?.cancel();

    try {
      final result = await session.stopAndSynthesize();
      // Raced by teardown while finalizing: the session is gone; do not install
      // an editable buffer or re-cancel (cancel already ran).
      if (!mounted ||
          _startGeneration != gen ||
          !identical(_streaming, session)) {
        return;
      }
      if (result == null) {
        cancel();
        return;
      }

      final amps = session.amplitudeTimeline;
      if (amps.isEmpty || amps.every((e) => e <= 1)) {
        showOkAlertDialog(
          context: context,
          title: L10n.of(context).oopsSomethingWentWrong,
          message: EmptyAudioException().toLocalizedString(context),
        );
        cancel();
        return;
      }

      _pendingResult = result;
      _pendingWaveform = _waveformFromAmplitudes(amps);
      if (_routeEmptyStreamToBatch(result)) {
        // #8209: an empty streamed transcript has nothing to review — send it
        // immediately through the batch path (reuses stopAndSend's
        // `_degradedToBatch && _pendingResult` branch) instead of parking in
        // batch-ready and forcing the learner to tap send a second time.
        await stopAndSend(onSend);
        return;
      }
      _editable = EditableTranscript(
        originalAsrText: result.transcript,
        words: session.finalWords,
        service: session.service,
        // Recording-time gated language (never send-time settings) so a mid-flow
        // L2 change cannot mislabel/mis-tokenize the transcript.
        langCode: session.lang,
        onInvalidateTranslationCache: _invalidateTranscriptTranslationCache,
      );
      // Repaint the editable field as the user types (drives dirty state + send
      // enablement in the row).
      _editable!.controller.addListener(_onEditableChanged);
    } finally {
      _finalizingToEditable = false;
      if (mounted) setState(() {});
    }
  }

  void _onEditableChanged() {
    if (mounted) setState(() {});
  }

  /// D7 guard hook: fired once, on the FIRST user edit (`editableClean →
  /// editableDirty`), so a stale cached transcript translation is dropped. The
  /// [EditableTranscript] already clears its own cached-translation entry; this
  /// is the recorder-side seam where wave 5 (which owns a sent message) will
  /// also clear that message's `pangea.stt_translation` cache. Pre-send there is
  /// no message yet, so wave 4 keeps the trigger + the buffer-level clear.
  void _invalidateTranscriptTranslationCache() {}

  /// Send the (possibly edited) streamed transcript's retained WAV (D7
  /// `editableClean`/`editableDirty → sent`). Reuses [_pendingResult] captured
  /// at stop — never re-transcribes. Wave 5 threads [streamingSendData] into
  /// `onVoiceMessageSend`; wave 4 sends the WAV with today's signature and holds
  /// the provenance in state.
  Future<void> sendEditedTranscript(VoiceMessageSend onSend) async {
    // Re-entrancy guard: UI disabling is not a concurrency boundary, so guard
    // in-method against a double-tap sending the same WAV twice.
    if (isSending) return;
    final result = _pendingResult;
    final editable = _editable;
    if (result == null || editable == null) return;
    // Snapshot the generation so a cancel/dispose that races the send does not
    // drive a post-await `setState`/`cancel` after teardown.
    final gen = _startGeneration;

    // Snapshot the D9 provenance BEFORE the await so the sent embed reflects the
    // buffer at send time (D8/D9): SENT text, edited/edit_distance/original_asr.
    final streamedTranscript = editable.buildSendData();

    setState(() => isSending = true);
    try {
      await onSend(
        result.wavPath,
        result.duration.inMilliseconds,
        _pendingWaveform ?? const <int>[],
        path_lib.basename(result.wavPath),
        streamedTranscript: streamedTranscript,
      );
    } catch (e, s) {
      // Send FAILED: leave the buffer editable (NOT terminal `sent`) so the user
      // can retry or keep editing, and provenance stays consistent — marking
      // sent before onSend succeeds would strand a failed send in `sent` while
      // later edits changed the text but not isEdited/editDistance (D9 corrupt).
      Logs().e('Unable to send edited streaming voice message', e, s);
      if (mounted && _startGeneration == gen) setState(() => isSending = false);
      return;
    }

    // Raced by cancel/dispose during the send: the buffer we sent is gone; do
    // not mark-sent a replaced buffer or `cancel()` after teardown.
    if (!mounted ||
        _startGeneration != gen ||
        !identical(_editable, editable)) {
      return;
    }
    // Send SUCCEEDED: mark sent (terminal), then tear down. `markCancelled`
    // inside _reset is a no-op on a `sent` buffer, so the outcome stays `sent`.
    editable.markSent();
    cancel();
  }
  // Pangea#

  void _reset() {
    WakelockPlus.disable();
    _recorderSubscription?.cancel();
    _audioRecorder?.stop();
    _audioRecorder = null;
    // #Pangea
    // Tear down the streaming capture + socket + retained buffer/WAV (D6).
    unawaited(_streaming?.teardown());
    _streaming = null;
    // Tear down the D7 editable buffer (mark cancelled, drop the controller +
    // held WAV/waveform). Idempotent.
    if (_editable != null) {
      _editable!.controller.removeListener(_onEditableChanged);
      _editable!.markCancelled();
      _editable!.dispose();
      _editable = null;
    }
    _pendingResult = null;
    _pendingWaveform = null;
    _degradedToBatch = false;
    _languageUnsupported = false;
    _dismissedBannerKind = null;
    isRecordingAnywhere = false;
    // Pangea#
    isSending = false;
    fileName = null;
    duration = Duration.zero;
    amplitudeTimeline.clear();
    isPaused = false;
  }

  void cancel() {
    // #Pangea
    // Invalidate any in-flight streaming start so a pending start aborts instead
    // of falling through to the batch recorder after this teardown.
    _startGeneration++;
    // Every send path calls cancel() AFTER awaiting onSend, so the recorder can
    // already be gone by then (the user left the chat mid-upload). dispose() has
    // run _reset() in that case, so there is nothing left to tear down — and
    // setState on a defunct State throws (CLIENT-AN1).
    if (!mounted) return;
    // Pangea#
    setState(() {
      _reset();
    });
  }

  void pause() {
    // #Pangea
    // The streaming socket has no resumable pause; the pause
    // control is hidden while streaming (RecordingInputRow). If it is reached
    // anyway, pausing ENDS the streaming session cleanly (D6) — the same reset
    // path as cancel tears down the mic + socket + buffer, never a no-op that
    // leaves them alive.
    if (_streaming != null) {
      cancel();
      return;
    }
    // Pangea#
    _audioRecorder?.pause();
    _recorderSubscription?.cancel();
    setState(() {
      isPaused = true;
    });
  }

  void resume() {
    // #Pangea
    if (_streaming != null) return;
    // Pangea#
    _audioRecorder?.resume();
    _subscribe();
    setState(() {
      isPaused = false;
    });
  }

  // #Pangea
  // Returns Future<void> (not void) so the caller can await the send completing
  // — the degrade batch path awaits onSend before tearing the session down, and
  // tests await the whole flow (H12). UI callers may still fire-and-forget it.
  Future<void> stopAndSend(VoiceMessageSend onSend) async {
    // D7 editable path: the mic already stopped and the WAV is synthesized;
    // send the (possibly edited) transcript's retained WAV.
    if (_editable != null) {
      await sendEditedTranscript(onSend);
      return;
    }
    // Post-`ready` admission-failure degrade (B4/B5): send the retained WAV via
    // the BATCH path — streamedTranscript OMITTED, so the server BATCH-transcribes
    // it — then cancel() (which tears the session down and disposes the temp WAV
    // AFTER onSend has read it). Must precede the `_streaming != null` branch:
    // the degrade deliberately keeps _streaming non-null (B5).
    if (_degradedToBatch && _pendingResult != null) {
      final r = _pendingResult!;
      setState(() => isSending = true);
      try {
        await onSend(
          r.wavPath,
          r.duration.inMilliseconds,
          _pendingWaveform ?? const <int>[],
          path_lib.basename(r.wavPath),
          // NOTE: streamedTranscript OMITTED -> today's batch transcription.
        );
      } catch (e, s) {
        Logs().e('Unable to send degraded streaming voice message', e, s);
        if (mounted) setState(() => isSending = false);
        return;
      }
      cancel(); // teardown + dispose the temp artifact (the send already read it)
      return;
    }
    // Streaming path with no editable buffer (e.g. the flag-gated direct-send
    // fallback): synthesize the retained WAV and send it (D5a).
    if (_streaming != null) {
      await _stopStreamingAndSend(onSend);
      return;
    }
    // Pangea#
    _recorderSubscription?.cancel();
    final path = await _audioRecorder?.stop();

    if (path == null) throw ('Recording failed!');
    const waveCount = AudioPlayerWidget.wavesCount;
    final step = amplitudeTimeline.length < waveCount
        ? 1
        : (amplitudeTimeline.length / waveCount).round();
    final waveform = <int>[];
    for (var i = 0; i < amplitudeTimeline.length; i += step) {
      waveform.add((amplitudeTimeline[i] / 100 * 1024).round());
    }

    // #Pangea
    if (amplitudeTimeline.isEmpty || amplitudeTimeline.every((e) => e <= 1)) {
      if (mounted) {
        showOkAlertDialog(
          context: context,
          title: L10n.of(context).oopsSomethingWentWrong,
          message: EmptyAudioException().toLocalizedString(context),
        );
      }
      cancel();
      return;
    }
    // Pangea#

    setState(() {
      isSending = true;
    });
    try {
      await onSend(path, duration.inMilliseconds, waveform, fileName);
    } catch (e, s) {
      Logs().e('Unable to send voice message', e, s);
      setState(() {
        isSending = false;
      });
      return;
    }

    cancel();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, this);
}

extension on AudioEncoder {
  String get fileExtension {
    switch (this) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacEld:
      case AudioEncoder.aacHe:
        return 'm4a';
      case AudioEncoder.opus:
        return 'ogg';
      case AudioEncoder.wav:
        return 'wav';
      case AudioEncoder.amrNb:
      case AudioEncoder.amrWb:
      case AudioEncoder.flac:
      case AudioEncoder.pcm16bits:
        throw UnsupportedError('Not yet used');
    }
  }
}
