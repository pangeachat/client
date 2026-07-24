import 'dart:async';

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
