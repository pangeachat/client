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
