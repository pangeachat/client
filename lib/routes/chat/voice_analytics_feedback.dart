import 'dart:async';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/stt_token_enrichment.dart';

/// The grammar + vocab counts shown in the transient analytics-feedback overlay.
typedef AnalyticsFeedbackCounts = ({int grammar, int vocab});

/// Runs [fetchGrammar] then [fetchVocab], BAILING (returning null) as soon as
/// [isMounted] reports false after either await -- so a caller never proceeds to
/// touch a disposed `BuildContext` after an `await`. This is the visual-feedback
/// path only (a transient overlay); it is fully decoupled from the
/// lifecycle-independent analytics RECORDING, which must always run regardless
/// of widget disposal. A `null` return simply means "the widget went away, skip
/// the overlay" -- never an error.
Future<AnalyticsFeedbackCounts?> guardedAnalyticsFeedbackCounts({
  required bool Function() isMounted,
  required Future<int> Function() fetchGrammar,
  required Future<int> Function() fetchVocab,
}) async {
  final grammar = await fetchGrammar();
  if (!isMounted()) return null;
  final vocab = await fetchVocab();
  if (!isMounted()) return null;
  return (grammar: grammar, vocab: vocab);
}

/// Runs the best-effort feedback [show] and SWALLOWS any failure (routing it to
/// [onError]) so a fire-and-forget feedback dispatch can NEVER escape as an
/// unhandled async error. Used symmetrically by both the flag-OFF analytics
/// path and (via the coordinator's own catch) the decouple path, since P1b made
/// `_showAnalyticsFeedback` async/heavier (H2). The returned future always
/// completes normally.
Future<void> guardFeedbackDispatch(
  Future<void> Function() show,
  FutureOr<void> Function(Object error, StackTrace stack) onError,
) async {
  try {
    await show();
  } catch (e, s) {
    // Contain BOTH a synchronous throw and an async rejection of the logger's
    // returned Future (ErrorHandler.logError returns Future<void>), so a failing
    // logger can never escape as an unhandled async error.
    reportErrorSafely(onError, e, s);
  }
}

/// The flag-OFF (inline) counterpart of `runVoiceTranscriptEnrichment`'s
/// analytics chain: the transcript is already tokenized when the send resolves,
/// so there is nothing to enrich -- only the best-effort overlay and the record.
///
/// LIFECYCLE-INDEPENDENT, exactly like [buildVoiceAnalyticsRecorder]: [sink] is
/// resolved at t0 while the widget is guaranteed live and passed in, so the
/// record NEVER reads a `BuildContext` after the send's awaits. Resolving it
/// late is unsound -- an unmounted `State.context` is `_element!`, which in a
/// release build is a bare null-check crash, and the learner's spoken
/// constructs go unrecorded (#8371).
///
/// Fully self-guarded so nothing escapes the caller's fire-and-forget: a
/// throwing [sink], a throwing [showFeedback], and a rejecting [onError] logger
/// are all contained. The returned future always completes normally.
///
/// [showFeedback] is dispatched BEFORE the record on purpose -- the overlay
/// reports how many constructs are NEW, a count the record itself would zero.
Future<void> recordInlineVoiceAnalytics({
  required SpeechToTextResponseModel stt,
  required String roomId,
  required String eventId,
  required VoiceAnalyticsSink sink,
  Future<void> Function(
    List<OneConstructUse> constructs,
    String eventId,
    String langCode,
  )?
  showFeedback,
  FutureOr<void> Function(Object error, StackTrace stack)? onError,
}) async {
  try {
    // An exhausted-fallback (`results: []`) or token-less transcript has
    // nothing to score, and reading `transcript` on one would throw.
    if (!stt.hasUsableTokens) return;
    final constructs = stt.constructs(roomId, eventId);
    if (constructs.isEmpty) return;
    final langCode = stt.langCode.split('-').first;

    if (showFeedback != null) {
      unawaited(
        guardFeedbackDispatch(
          () => showFeedback(constructs, eventId, langCode),
          (e, s) => reportErrorSafely(onError, e, s),
        ),
      );
    }
    await sink(eventId, constructs, langCode);
  } catch (e, s) {
    reportErrorSafely(onError, e, s);
  }
}
