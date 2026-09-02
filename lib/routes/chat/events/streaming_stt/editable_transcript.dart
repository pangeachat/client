import 'package:flutter/widgets.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_diff_spans.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_provenance.dart';

/// The explicit D7 editable-buffer states.
///
/// `recording` → (stop) → `finalizing` (bounded drain, wave 3) → `editableClean`
/// (settled final is the buffer, no user edit yet) → `editableDirty` (first real
/// user keystroke) → `sent` | `cancelled`.
///
/// The recorder's streaming session (wave 3) owns `recording`/`finalizing`; an
/// [EditableTranscript] is built at the `finalizing → editableClean` hand-off
/// with the settled final. The enum still spans both halves so the ONE machine
/// — and the streaming-update discard rule keyed on it — is complete and
/// testable end to end.
enum EditableTranscriptState {
  recording,
  finalizing,
  editableClean,
  editableDirty,
  sent,
  cancelled,
}

/// A [TextEditingController] that distinguishes SYSTEM writes (the settled-final
/// pre-fill / a late final re-settle) from USER keystrokes, mirroring
/// [PangeaTextController.setSystemText]. A system write flips [isApplyingSystemText]
/// for the duration of the synchronous `text =` assignment (which notifies
/// listeners synchronously), so the [EditableTranscript] listener can tell the
/// two apart and only a real keystroke moves `editableClean → editableDirty`.
class EditableTranscriptController extends TextEditingController {
  EditableTranscriptController({super.text});

  bool _applyingSystemText = false;

  /// The settled ASR base the live edit-diff colors against (D10). Kept in sync
  /// with [EditableTranscript.originalAsrText] by the owning transcript so the
  /// field shows changed words orange / unchanged green as the learner types.
  /// Empty until a base settles, in which case [buildTextSpan] renders plain text.
  String diffBase = '';

  /// True only while a [setSystemText] assignment is in flight.
  bool get isApplyingSystemText => _applyingSystemText;

  /// Write [newText] as a SYSTEM edit (does NOT set the buffer dirty).
  void setSystemText(String newText) {
    _applyingSystemText = true;
    try {
      if (text != newText) text = newText;
    } finally {
      _applyingSystemText = false;
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (diffBase.isEmpty || text.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    return TextSpan(
      style: style,
      children: sttDiffTextSpans(
        diffBase,
        text,
        baseStyle: style,
        changedColor: AppConfig.warningByTheme(context),
        unchangedColor: AppConfig.successByTheme(context),
      ),
    );
  }
}

/// The D7 editable-transcript state machine (Phase-2 wave 4): owns the settled
/// transcript buffer after a streaming recording stops, distinguishes system
/// pre-fills from user edits, gates late streaming updates, and computes the D9
/// provenance ([StreamingSttSendData]) the send path (wave 5) consumes.
///
/// Flutter-light and self-contained so it is unit-testable directly via seams
/// (no mic, no socket). The recorder owns one instance while the editable field
/// is shown, drives late finals through [applyStreamingUpdate], and reads
/// [buildSendData] / [isEdited] / [editDistance] at send.
class EditableTranscript {
  /// Build a settled buffer (the recorder's path): starts in
  /// [EditableTranscriptState.editableClean] with [originalAsrText] pre-filled
  /// as SYSTEM text. [words]/[service] are the streaming provenance carried into
  /// [buildSendData]. [onInvalidateTranslationCache] fires once, on the first
  /// user edit (the `editableClean → editableDirty` transition), so a stale
  /// cached transcript translation is dropped (D7 guard).
  EditableTranscript({
    required String originalAsrText,
    List<SttWord> words = const <SttWord>[],
    String service = '',
    String langCode = '',
    EditableTranscriptController? controller,
    void Function()? onInvalidateTranslationCache,
  }) : this._(
         originalAsrText: originalAsrText,
         words: words,
         service: service,
         langCode: langCode,
         initialState: EditableTranscriptState.editableClean,
         controller: controller,
         onInvalidateTranslationCache: onInvalidateTranslationCache,
       );

  /// Build a buffer that begins in [EditableTranscriptState.recording] and is
  /// driven through the full lifecycle via [applyStreamingUpdate] /
  /// [beginFinalizing] / [settle]. Used to exercise the whole machine in tests.
  EditableTranscript.fromRecording({
    List<SttWord> words = const <SttWord>[],
    String service = '',
    String langCode = '',
    EditableTranscriptController? controller,
    void Function()? onInvalidateTranslationCache,
  }) : this._(
         originalAsrText: '',
         words: words,
         service: service,
         langCode: langCode,
         initialState: EditableTranscriptState.recording,
         controller: controller,
         onInvalidateTranslationCache: onInvalidateTranslationCache,
       );

  EditableTranscript._({
    required String originalAsrText,
    required List<SttWord> words,
    required String service,
    required String langCode,
    required EditableTranscriptState initialState,
    required EditableTranscriptController? controller,
    required void Function()? onInvalidateTranslationCache,
  }) : _originalAsrText = originalAsrText,
       _words = words,
       _service = service,
       _langCode = langCode,
       _state = initialState,
       _onInvalidateTranslationCache = onInvalidateTranslationCache,
       _ownsController = controller == null,
       controller = controller ?? EditableTranscriptController() {
    if (initialState == EditableTranscriptState.editableClean) {
      // Seed the field with the settled final as a SYSTEM write — must NOT set
      // the buffer dirty.
      this.controller.setSystemText(originalAsrText);
      this.controller.diffBase = _originalAsrText;
    }
    this.controller.addListener(_onControllerChanged);
  }

  /// The editable field's controller. The recorder wires this into the
  /// `TextField`; user keystrokes on it drive the dirty transition.
  final EditableTranscriptController controller;
  final bool _ownsController;
  final void Function()? _onInvalidateTranslationCache;

  List<SttWord> _words;
  String _service;
  final String _langCode;
  String _originalAsrText;
  EditableTranscriptState _state;
  bool _reachedDirty = false;
  bool _disposed = false;

  /// A cached transcript translation of the settled final, if some surface
  /// computed one. Cleared on the first user edit (D7 guard) since the edit
  /// invalidates it. Held here so the invalidation has a concrete entry to drop
  /// in addition to firing [_onInvalidateTranslationCache].
  String? cachedTranslation;

  EditableTranscriptState get state => _state;

  /// The verbatim settled ASR final captured at `editableClean` (or re-settled
  /// by a later final while still clean). The D9 `original_asr`.
  String get originalAsrText => _originalAsrText;

  /// The current buffer text (verbatim, or the user's edit).
  String get currentText => controller.text;

  /// Whether the learner meaningfully edited the transcript: they made a real
  /// keystroke ([_reachedDirty]) AND the resulting text NET-differs from the
  /// settled ASR original ([editDistance] > 0). The delta check is what fixes
  /// the "orange flag always shows" bug — a buffer the learner left unchanged,
  /// typed into and reverted, or that only tripped a spurious web focus/compose
  /// event, carries `edited=false` with `edit_distance=0`. The keystroke check
  /// guards against a non-user system write (a late-final re-settle) that shifts
  /// the text before the base is re-aligned.
  bool get isEdited => _reachedDirty && editDistance > 0;

  /// `Levenshtein(originalAsrText, currentText)` at grapheme granularity,
  /// computed on demand (the send reads it). `0` on a verbatim buffer.
  int get editDistance => sttEditDistance(_originalAsrText, currentText);

  /// The streaming per-word timings (align with [originalAsrText] only).
  List<SttWord> get words => _words;

  /// The streaming engine that produced the transcript.
  String get service => _service;

  bool get _acceptsStreaming =>
      _state == EditableTranscriptState.recording ||
      _state == EditableTranscriptState.finalizing ||
      _state == EditableTranscriptState.editableClean;

  /// Apply a streaming partial/final from the relay. Applied ONLY in
  /// `recording`/`finalizing`/`editableClean`; DISCARDED (a no-op returning
  /// false) in `editableDirty`/`sent`/`cancelled` — a late final must never
  /// clobber a user edit. Writes are SYSTEM edits, so applying one never trips
  /// the dirty transition.
  ///
  /// In `editableClean` ONLY a final/`speechFinal` is accepted, and it
  /// re-settles the verbatim base ([originalAsrText]) AND its word timings
  /// ([words]) together. A NON-final partial is discarded in `editableClean`:
  /// applying one would write [currentText] while leaving [originalAsrText]
  /// (and [isEdited]) unchanged, so provenance could read `isEdited=false` with
  /// `editDistance>0` — a corrupt D9 record. During `recording`/`finalizing`
  /// the base is not yet settled, so partials there flow through freely.
  bool applyStreamingUpdate(SttPartial partial) {
    if (!_acceptsStreaming) return false;
    final isFinal = partial.isFinal || partial.speechFinal;
    if (_state == EditableTranscriptState.editableClean && !isFinal) {
      return false;
    }
    controller.setSystemText(partial.transcript);
    if (isFinal) {
      _originalAsrText = partial.transcript;
      controller.diffBase = partial.transcript;
      // Re-settle the timings with the base so [words] never goes stale
      // against a newer [originalAsrText] (D9 alignment).
      _words = partial.words;
    }
    return true;
  }

  /// `recording → finalizing` (stop pressed; the bounded drain runs).
  void beginFinalizing() {
    if (_state == EditableTranscriptState.recording) {
      _state = EditableTranscriptState.finalizing;
    }
  }

  /// `recording`/`finalizing → editableClean`: capture [finalText] as the
  /// verbatim base and pre-fill the field (SYSTEM write, not dirty).
  void settle(String finalText, {List<SttWord>? words, String? service}) {
    if (_state != EditableTranscriptState.recording &&
        _state != EditableTranscriptState.finalizing) {
      return;
    }
    _originalAsrText = finalText;
    controller.diffBase = finalText;
    // Always re-align [words] with the newly settled base: keeping the prior
    // (older-final) timings when [words] is omitted would leave D9 word timings
    // pointing at a different transcript than [originalAsrText] (same alignment
    // hazard [applyStreamingUpdate] guards on a late-final re-settle).
    _words = words ?? const <SttWord>[];
    if (service != null) _service = service;
    _state = EditableTranscriptState.editableClean;
    controller.setSystemText(finalText);
  }

  /// `editableClean`/`editableDirty → sent`. Idempotent guard: only from an
  /// editable state.
  void markSent() {
    if (_state == EditableTranscriptState.editableClean ||
        _state == EditableTranscriptState.editableDirty) {
      _state = EditableTranscriptState.sent;
    }
  }

  /// → `cancelled` (cancel/dispose/navigation). Terminal; further streaming
  /// updates are discarded. A buffer that already reached `sent` (a successful
  /// send) STAYS `sent` — teardown after a successful send must not relabel it
  /// `cancelled`, so the terminal outcome stays honest.
  void markCancelled() {
    if (_state == EditableTranscriptState.sent) return;
    _state = EditableTranscriptState.cancelled;
  }

  void _onControllerChanged() {
    // A SYSTEM write (pre-fill / late-final re-settle) is not a user keystroke.
    if (controller.isApplyingSystemText) return;
    if (_state != EditableTranscriptState.editableClean) return;
    // First real user keystroke on a clean buffer: go dirty + invalidate.
    _state = EditableTranscriptState.editableDirty;
    _reachedDirty = true;
    cachedTranslation = null;
    _onInvalidateTranslationCache?.call();
  }

  /// Snapshot the D9 provenance for the send path (wave 5). Valid ONLY once the
  /// base has settled (`editableClean`/`editableDirty`/`sent`). Before settle
  /// the base is still empty while partials drive [currentText], so a snapshot
  /// would report a spurious `editDistance>0` with `isEdited=false` — a corrupt
  /// D9 record. Guarded with a hard throw (never a silent bad snapshot); the
  /// production VM only ever holds an editable buffer post-settle.
  StreamingSttSendData buildSendData() {
    if (_state == EditableTranscriptState.recording ||
        _state == EditableTranscriptState.finalizing) {
      throw StateError(
        'buildSendData() called before settle (state=$_state); the D9 '
        'provenance base is not settled yet.',
      );
    }
    return StreamingSttSendData(
      text: currentText,
      originalAsrText: _originalAsrText,
      isEdited: isEdited,
      editDistance: editDistance,
      words: _words,
      service: _service,
      langCode: _langCode,
    );
  }

  /// Detach the listener and (if owned) dispose the controller. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.removeListener(_onControllerChanged);
    if (_ownsController) controller.dispose();
  }
}
