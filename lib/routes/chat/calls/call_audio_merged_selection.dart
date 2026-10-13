import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';

/// The ONE merged `pangea.call_audio_merged` recording to show as a call's
/// "Full call" primary row, or null when none should be shown.
///
/// Pure: no widgets, no fetch, no clock. Everything it decides on is in its two
/// arguments -- the merged events read for the call, and how many
/// `pangea.call_audio` halves the room shows -- so the whole of the player's
/// two dedup/suppression rules can be pinned by a plain unit test without any
/// of the rendering around it. See the merge design doc's "The player".
///
/// Two rules, applied in this order:
///
/// 1. **v1-scope suppression.** More than two halves means a mid-call device
///    switch, which is out of v1 scope: v1 posts no merge for such a call and
///    the player shows NO merged row, listing the individual halves instead.
///    This is the enforced "switched calls get no v1 merge" guarantee, and it
///    holds EVEN IF a stale two-half merged event was posted before a third
///    half arrived -- so it is checked FIRST, before the events are even looked
///    at. [halfCount] is the count the caller sees today (the length of the
///    per-device recordings list), which is exactly the "more than two halves"
///    the guarantee is stated against.
///
/// 2. **Dedup by a TOTAL order.** Among the merged events for one call --
///    duplicate posts persist in room history, so there can be more than one --
///    exactly one row wins: the GREATEST [CallAudioMergedContent.coverageCardinality]
///    (a merge that covers more halves is the fuller recording), then, to break
///    a tie, the LOWER [CallAudioMergedContent.coverageHash] (a stable content
///    digest, so two devices that mixed the same coverage agree without a
///    clock), then the LOWER [CallAudioMergedRecording.eventId] (globally unique,
///    so the order is total and the winner never depends on input order or sort
///    stability).
///
/// The input list is never mutated: the sort runs on a copy.
CallAudioMergedRecording? selectMergedRow(
  List<CallAudioMergedRecording> merged,
  int halfCount,
) {
  // Rule 1, ahead of everything else: a switched call gets no merged row, even
  // if a stale two-half merge is present in [merged].
  if (halfCount > 2) return null;

  if (merged.isEmpty) return null;

  // Rule 2, over a COPY so the caller's list keeps its own order.
  final ranked = [...merged]..sort(_byTotalOrder);
  return ranked.first;
}

/// Ranks two merged recordings by the design's total order: greatest coverage
/// cardinality, then lower coverage hash, then lower event id. Returns a
/// negative number when [a] should sort BEFORE [b] (i.e. [a] is the better
/// row), so `sort`'s first element is the winner.
int _byTotalOrder(CallAudioMergedRecording a, CallAudioMergedRecording b) {
  // Greatest cardinality first: b before a when b covers more, so the fuller
  // merge sorts earlier.
  final byCardinality = b.content.coverageCardinality.compareTo(
    a.content.coverageCardinality,
  );
  if (byCardinality != 0) return byCardinality;

  // Then the LOWER coverage hash. A stable digest, so this tiebreak is the same
  // on every device that computes it -- see [CallAudioMergedContent.coverageHash].
  final byHash = a.content.coverageHash.compareTo(b.content.coverageHash);
  if (byHash != 0) return byHash;

  // Then the LOWER event id. Globally unique, so this can never itself tie for
  // two distinct events, which is what makes the order total and the outcome
  // independent of the input's order.
  return a.eventId.compareTo(b.eventId);
}
