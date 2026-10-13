import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';

/// Whether the recordings of one call are the WHOLE call (client#9173).
///
/// A learner can move a call between their devices, so one speaker's side of
/// a call can be several recordings: the device it started on, linked by
/// `handed_over_to` / `continued_from` to the device it moved to. A merge of
/// the call is only honest when it covers every one of them, so before
/// anything is mixed, retired or shown, the set of known halves H is CLOSED:
///
/// * exactly two speakers, both members of the direct chat;
/// * every link names a device that has a half from the same speaker;
/// * each speaker has ONE half with no links, or ONE chain of linked halves no
///   longer than [maxChain].
///
/// A link to a half not yet in the room keeps the call OPEN: the half may still
/// arrive. Two halves from one speaker that are not chained -- two devices
/// that both carried on -- can never close, and neither can a broken chain.
sealed class CallClosure {
  const CallClosure();
}

/// H is the whole call. [chains] holds each speaker's halves in call order.
class ClosedCall extends CallClosure {
  final Map<String, List<CallAudioRecording>> chains;

  const ClosedCall(this.chains);

  /// Every half of the call.
  List<CallAudioRecording> get halves => [
    for (final chain in chains.values) ...chain,
  ];

  /// Whether every speaker has a single unlinked half: the plain two-device
  /// call every merge before #9173 was made from.
  bool get isPlain => chains.values.every((chain) => chain.length == 1);

  /// Where each half that handed the call on stops counting, on the SFU's
  /// clock: the moment the device it moved to started recording. Keyed by
  /// event id; halves that end their speaker's chain are absent.
  Map<String, int> get trimEndSfuMs => {
    for (final chain in chains.values)
      for (var i = 0; i + 1 < chain.length; i++)
        if (chain[i + 1].content.fileStartSfuMs != null)
          chain[i].eventId: chain[i + 1].content.fileStartSfuMs!,
  };

  /// The span the merge has to cover, on the SFU's clock: from the earliest
  /// first sample to the latest kept one, each handed-on half cut where its
  /// successor began. Null when any half cannot be placed.
  int? get trimmedSpanMs {
    final trims = trimEndSfuMs;
    int? start;
    int? end;
    for (final half in halves) {
      final s = half.content.fileStartSfuMs;
      if (s == null) return null;
      var e = s + half.content.durationMs;
      final trim = trims[half.eventId];
      if (trim != null && trim < e) e = trim;
      start = start == null || s < start ? s : start;
      end = end == null || e > end ? e : end;
    }
    if (start == null || end == null) return null;
    return end - start;
  }

  /// The earliest first sample of any half.
  int? get startSfuMs {
    int? start;
    for (final half in halves) {
      final s = half.content.fileStartSfuMs;
      if (s == null) return null;
      start = start == null || s < start ? s : start;
    }
    return start;
  }
}

/// H is not the whole call YET: a speaker is missing, or a link names a half
/// that has not arrived.
class OpenCall extends CallClosure {
  final String reason;
  const OpenCall(this.reason);
}

/// H can never be the whole call.
class BrokenCall extends CallClosure {
  final String reason;
  const BrokenCall(this.reason);
}

/// The longest chain of devices one speaker's side may span.
const maxChain = 4;

/// Closes [halves] against the call's two [participants]. Halves from anyone
/// else are not part of the call and are left out.
CallClosure closeCall(
  Iterable<CallAudioRecording> halves,
  Set<String> participants,
) {
  if (participants.length != 2) return const OpenCall('participants-unknown');
  final bySender = <String, List<CallAudioRecording>>{};
  for (final half in halves) {
    if (!participants.contains(half.senderId)) continue;
    bySender.putIfAbsent(half.senderId, () => []).add(half);
  }
  // A speaker whose halves can never chain breaks the call however much of it
  // is still to arrive, so that is decided before anything waits.
  final chains = <String, List<CallAudioRecording>>{};
  CallClosure? open;
  for (final entry in bySender.entries) {
    final (ordered, problem) = _chainOf(entry.value);
    if (problem is BrokenCall) return problem;
    if (problem != null) open ??= problem;
    if (ordered != null) chains[entry.key] = ordered;
  }
  if (bySender.length < 2) return const OpenCall('a-speaker-is-missing');
  return open ?? ClosedCall(chains);
}

/// One speaker's halves in call order, or why they are not one chain.
(List<CallAudioRecording>?, CallClosure?) _chainOf(
  List<CallAudioRecording> halves,
) {
  final byDevice = <String, CallAudioRecording>{};
  for (final half in halves) {
    final device = half.content.deviceId;
    if (device == null) {
      // A half that cannot name its device cannot be linked to; alone it is
      // the plain case, beside others it is a second unchained half.
      if (halves.length == 1) return ([half], null);
      return (null, const BrokenCall('unlinked-same-sender'));
    }
    if (byDevice.containsKey(device)) {
      return (null, const BrokenCall('duplicate-device-half'));
    }
    byDevice[device] = half;
  }

  // Every link must name a half from this speaker. One that does not may still
  // arrive, so the call stays open on it.
  for (final half in halves) {
    for (final link in [
      half.content.continuedFrom,
      half.content.handedOverTo,
    ]) {
      if (link != null && !byDevice.containsKey(link)) {
        return (null, const OpenCall('linked-half-missing'));
      }
    }
  }

  // Edges from either side of a link; both sides, where both are written,
  // must agree.
  final next = <String, String>{};
  final prev = <String, String>{};
  bool addEdge(String from, String to) {
    if (from == to) return false;
    if ((next[from] ?? to) != to || (prev[to] ?? from) != from) return false;
    next[from] = to;
    prev[to] = from;
    return true;
  }

  for (final half in halves) {
    final device = half.content.deviceId!;
    final to = half.content.handedOverTo;
    final from = half.content.continuedFrom;
    if (to != null && !addEdge(device, to)) {
      return (null, const BrokenCall('inconsistent-links'));
    }
    if (from != null && !addEdge(from, device)) {
      return (null, const BrokenCall('inconsistent-links'));
    }
  }

  if (halves.length == 1) return (halves, null);
  final unlinked = byDevice.keys.where(
    (d) => !next.containsKey(d) && !prev.containsKey(d),
  );
  if (unlinked.isNotEmpty) {
    return (null, const BrokenCall('unlinked-same-sender'));
  }
  if (halves.length > maxChain) {
    return (null, const BrokenCall('chain-too-long'));
  }

  final heads = byDevice.keys.where((d) => !prev.containsKey(d)).toList();
  if (heads.length != 1) return (null, const BrokenCall('inconsistent-links'));
  final ordered = <CallAudioRecording>[];
  String? at = heads.single;
  while (at != null && ordered.length <= halves.length) {
    ordered.add(byDevice[at]!);
    at = next[at];
  }
  if (ordered.length != halves.length) {
    return (null, const BrokenCall('inconsistent-links'));
  }
  return (ordered, null);
}

/// Whether [merged] is a trustworthy merge of the WHOLE call [closed]: the ONE
/// test every reader of a merge applies -- the merge coordinator before it
/// retires a call or posts over a merge, the transcript view before it shows
/// one, the backfill before it trusts one's sources.
///
/// Written by a participant for this call; covering exactly the halves of H,
/// no more and no fewer; starting where H starts; long enough to hold H's
/// trimmed span (a second of slack for rounding); and saying it is complete. A
/// merge written before `complete` existed is trusted only for the plain
/// two-half call, which is the only kind those writers made.
bool isTrustedWholeMerge({
  required CallAudioMergedRecording merged,
  required ClosedCall closed,
  required Set<String> participants,
  required String callKey,
}) {
  final content = merged.content;
  if (!participants.contains(merged.senderId)) return false;
  if (content.callKey != callKey) return false;
  final halves = closed.halves;
  final listed = content.sourceEventIds.toSet();
  if (listed.length != halves.length ||
      !halves.every((h) => listed.contains(h.eventId))) {
    return false;
  }
  final start = closed.startSfuMs;
  final span = closed.trimmedSpanMs;
  if (start == null || span == null) return false;
  if (content.mergedStartSfuMs != start) return false;
  if (content.durationMs < span - 1000) return false;
  final complete = content.complete;
  if (complete == null) return closed.isPlain && halves.length == 2;
  return complete;
}

/// The one merge to show or trust for [closed], or null when none is. Among
/// trusted merges (all of which cover exactly H) the smallest event id wins,
/// so every reader settles on the same one.
CallAudioMergedRecording? selectTrustedMerge({
  required Iterable<CallAudioMergedRecording> merged,
  required ClosedCall closed,
  required Set<String> participants,
  required String callKey,
}) {
  CallAudioMergedRecording? best;
  for (final m in merged) {
    if (!isTrustedWholeMerge(
      merged: m,
      closed: closed,
      participants: participants,
      callKey: callKey,
    )) {
      continue;
    }
    if (best == null || m.eventId.compareTo(best.eventId) < 0) best = m;
  }
  return best;
}
