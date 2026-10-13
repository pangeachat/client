import 'package:fluffychat/routes/chat/calls/call_audio_closure.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';

/// What this device should do about one call's `pangea.call_audio` halves.
///
/// Exactly one of these comes back from [decideCallAudioMerge], and the five
/// shapes are the whole vocabulary the coordinator (P3b) needs to drive its
/// retry/retire logic: [AlreadyMerged] and [TerminallyIneligible] both mean
/// "stop looking at this call forever", [PendingIncomplete] means "index it
/// and wait for a later trigger", [NotCandidate] means "some OTHER device
/// will do this, stand down", and [Mergeable] carries everything a merge
/// attempt needs to actually run.
///
/// A sealed class rather than an enum because [TerminallyIneligible] carries
/// a reason and [Mergeable] carries three fields — a `switch` over this type
/// is exhaustive and the compiler enforces that every caller handles all
/// five, the same guarantee an enum-only vocabulary could not give here.
sealed class CallAudioMergeVerdict {
  const CallAudioMergeVerdict();
}

/// A TRUSTED merge of the whole call already exists (`isTrustedWholeMerge`).
///
/// Retire: remove any durable index entry for this call and do nothing more.
/// A merge that is not trusted -- partial, overclaiming, invalid -- never
/// produces this (client#9173).
class AlreadyMerged extends CallAudioMergeVerdict {
  const AlreadyMerged();

  @override
  bool operator ==(Object other) => other is AlreadyMerged;

  @override
  int get hashCode => (AlreadyMerged).hashCode;

  @override
  String toString() => 'AlreadyMerged()';
}

/// This call will never be merged by this decision core, and it never
/// becomes eligible later -- retire it (remove any durable index entry) and
/// never revisit.
///
/// [reason] is one of a small closed set, named for logging and for tests to
/// assert against directly rather than pattern-matching a free-form message:
/// - `'not-a-dm'` -- the room is not a 1:1 DM (a group/non-DM call is out of
///   v1 scope).
/// - a closure reason from `closeCall` (client#9173): `'unlinked-same-sender'`
///   (two of one speaker's devices both carried on), `'inconsistent-links'`,
///   `'chain-too-long'`, `'duplicate-device-half'`.
/// - `'supersession-cap'` -- the call already holds [maxSupersessions]
///   merges.
/// - `'unplaceable-half'` -- a truncated, null-`fileStartSfuMs`, or
///   non-pcm16-mono half can never become a clean expected half no matter how
///   many more times this call is evaluated.
class TerminallyIneligible extends CallAudioMergeVerdict {
  final String reason;

  const TerminallyIneligible(this.reason);

  @override
  bool operator ==(Object other) =>
      other is TerminallyIneligible && other.reason == reason;

  @override
  int get hashCode => Object.hash(TerminallyIneligible, reason);

  @override
  String toString() => 'TerminallyIneligible($reason)';
}

/// This call is not yet decidable, but it MAY become so later -- index it (if
/// not already) and wait for a later trigger (a sync, a periodic drain, a
/// startup scan) to re-evaluate it. Never treated as terminal.
///
/// Covers three distinct situations, all with the same "wait" verdict: the
/// room's DM-ness has not loaded yet (room state may still be syncing), fewer
/// than two halves have been seen (the peer's half has not arrived), or the
/// two halves seen so far are not yet known to be from two distinct DM
/// members.
class PendingIncomplete extends CallAudioMergeVerdict {
  const PendingIncomplete();

  @override
  bool operator ==(Object other) => other is PendingIncomplete;

  @override
  int get hashCode => (PendingIncomplete).hashCode;

  @override
  String toString() => 'PendingIncomplete()';
}

/// The call is complete and eligible -- exactly two placeable halves from the
/// DM's two distinct members -- but THIS device posted neither of them.
///
/// Stand down: some other device (one of the two posters) is the one that
/// evaluates this call to [Mergeable] and does the merge. A caller must never
/// assume it can fall back to some other index into the half list here --
/// this verdict exists precisely so nothing downstream needs to.
class NotCandidate extends CallAudioMergeVerdict {
  const NotCandidate();

  @override
  bool operator ==(Object other) => other is NotCandidate;

  @override
  int get hashCode => (NotCandidate).hashCode;

  @override
  String toString() => 'NotCandidate()';
}

/// This call has exactly two placeable halves from the DM's two distinct
/// members, and this device posted one of them -- a merge attempt may run.
class Mergeable extends CallAudioMergeVerdict {
  /// This device's index among the two candidates, sorted by `(senderId,
  /// deviceId)` ascending. Used by the coordinator to stagger attempts (the
  /// lower rank tries first; a higher rank waits and stands down if the lower
  /// rank's merged event shows up first).
  final int myRank;

  /// The two halves' `eventId`s, sorted ascending -- the coverage a resulting
  /// merged event claims, and stable regardless of the order [halves] arrived
  /// in.
  final List<String> coverageEventIds;

  /// The minimum `fileStartSfuMs` across the two halves -- where the earlier
  /// of the two recordings starts on the SFU's own clock -- or null if either
  /// half's is null.
  ///
  /// [Mergeable] is only ever constructed after step 7 has confirmed both
  /// halves are placeable, and placeable requires a non-null
  /// `fileStartSfuMs`, so this is never actually null on a real verdict; the
  /// field stays nullable rather than `late`/force-unwrapped so a caller
  /// reads its type honestly instead of trusting an invariant it cannot see.
  final int? mergedStartSfuMs;

  /// Where each half that handed the call on is cut, by event id (see
  /// `ClosedCall.trimEndSfuMs`). Empty for a call nobody moved.
  final Map<String, int> trimEndSfuMs;

  const Mergeable({
    required this.myRank,
    required this.coverageEventIds,
    required this.mergedStartSfuMs,
    this.trimEndSfuMs = const {},
  });

  @override
  bool operator ==(Object other) =>
      other is Mergeable &&
      other.myRank == myRank &&
      other.mergedStartSfuMs == mergedStartSfuMs &&
      _listEquals(other.coverageEventIds, coverageEventIds);

  @override
  int get hashCode => Object.hash(
    Mergeable,
    myRank,
    mergedStartSfuMs,
    Object.hashAll(coverageEventIds),
  );

  @override
  String toString() =>
      'Mergeable(myRank: $myRank, coverageEventIds: $coverageEventIds, '
      'mergedStartSfuMs: $mergedStartSfuMs)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One `(senderId, deviceId)` pair, sortable into the deterministic candidate
/// order [decideCallAudioMerge] ranks devices by.
///
/// A device id that was actually null on the half is carried here as `''`
/// rather than as null -- ONLY for this sort key, exactly the substitution
/// [CallTranscriptContent.usableDeviceId]-keyed callers already make for
/// txnId scoping. It never changes what a half's own `content.deviceId`
/// reads as; it only gives the total order something to compare when the
/// OTHER poster's half is placeable but did not name a device.
class _Candidate {
  final String senderId;
  final String deviceId;

  const _Candidate(this.senderId, this.deviceId);

  @override
  bool operator ==(Object other) =>
      other is _Candidate &&
      other.senderId == senderId &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(senderId, deviceId);
}

/// A TOTAL ORDER over candidates: `senderId` first, then `deviceId`.
///
/// Modelled on `capture_election.dart`'s `_sortsBefore` SHAPE -- a small,
/// pure, two-key comparator any device can compute alone and every device
/// computes identically -- but NOT that function itself: `_sortsBefore`
/// ranks `(canCapture, deviceId)` and is self-anchored to one device's own
/// view of its siblings, where this ranks two Matrix identities directly so
/// that every device evaluating the SAME two halves reaches the SAME order.
int _compareCandidates(_Candidate a, _Candidate b) {
  final bySender = a.senderId.compareTo(b.senderId);
  if (bySender != 0) return bySender;
  return a.deviceId.compareTo(b.deviceId);
}

/// A half is placeable iff it could ever become part of a clean merged file:
/// this app's own codec, mono, a known start on the SFU clock, and not cut
/// short by the recording ceiling.
bool _isPlaceable(CallAudioRecording half) =>
    half.content.codec == kCallAudioCodec &&
    half.content.channels == 1 &&
    half.content.fileStartSfuMs != null &&
    half.content.truncated == false;

/// Whether [half] is one THIS device itself posted.
///
/// Both sides of the identity must be present and equal: an absent
/// [myDeviceId] (this device does not know its own device id yet) or an
/// absent `half.content.deviceId` (the half did not name one) can never
/// match, on the same terms every other device-id comparison in this file
/// treats absence as "no claim", never as a wildcard.
bool _matchesMe(CallAudioRecording half, String myUserId, String? myDeviceId) =>
    half.senderId == myUserId &&
    half.content.deviceId != null &&
    myDeviceId != null &&
    half.content.deviceId == myDeviceId;

/// Decides what this device should do about one call's `pangea.call_audio`
/// halves -- PURELY, from the inputs given. No I/O, no clock.
///
/// [halves] -- every `pangea.call_audio` half found for this call. [merged] --
/// every `pangea.call_audio_merged` event found for it. [participants] -- the
/// direct chat's two members. [isDmRoom] is null while the room is not yet
/// known, which is NOT the same as false.
///
/// The order is load-bearing (client#9173):
/// 1. `isDmRoom == false` -> [TerminallyIneligible] (`'not-a-dm'`); null ->
///    [PendingIncomplete].
/// 2. H, the halves, cannot ever be the whole call (`closeCall`) ->
///    [TerminallyIneligible] with the closure's reason -- e.g.
///    `'unlinked-same-sender'`, two devices of one speaker that both carried
///    on.
/// 3. H is not the whole call YET -> [PendingIncomplete].
/// 4. A TRUSTED merge of exactly H exists (`isTrustedWholeMerge`) ->
///    [AlreadyMerged]. A merge that is invalid, overclaims, or covers less than
///    H retires nothing: the call is merged again under the coverage that is
///    true, which is a different transaction.
/// 5. A half cannot be placed -> [TerminallyIneligible] (`'unplaceable-half'`).
/// 6. [maxSupersessions] earlier merges of part of H already exist ->
///    [TerminallyIneligible] (`'supersession-cap'`).
/// 7. This device posted no half of H, or its half handed the call on (a
///    device the call moved FROM never mixes) -> [NotCandidate].
/// 8. Otherwise [Mergeable], ranked among the halves that END a speaker's
///    side -- the only halves whose devices mix.
CallAudioMergeVerdict decideCallAudioMerge({
  required List<CallAudioRecording> halves,
  required List<CallAudioMergedRecording> merged,
  required bool? isDmRoom,
  required Set<String> participants,
  required String callKey,
  required String myUserId,
  required String? myDeviceId,
}) {
  if (isDmRoom == false) return const TerminallyIneligible('not-a-dm');
  if (isDmRoom == null) return const PendingIncomplete();

  final closure = closeCall(halves, participants);
  final ClosedCall closed;
  switch (closure) {
    case BrokenCall(:final reason):
      return TerminallyIneligible(reason);
    case OpenCall():
      return const PendingIncomplete();
    case final ClosedCall c:
      closed = c;
  }

  if (merged.any(
    (m) => isTrustedWholeMerge(
      merged: m,
      closed: closed,
      participants: participants,
      callKey: callKey,
    ),
  )) {
    return const AlreadyMerged();
  }

  final h = closed.halves;
  if (h.any((half) => !_isPlaceable(half))) {
    return const TerminallyIneligible('unplaceable-half');
  }
  // Only real supersessions count toward the cap: participants' merges of this
  // call that covered a STRICT part of what H is now -- each one an earlier,
  // smaller whole the call has since grown past. A merge naming anything outside H
  // is not a step H grew from, so a flood of those cannot use up the cap.
  final ids = {for (final half in h) half.eventId};
  final superseded = {
    for (final m in merged)
      if (participants.contains(m.senderId) &&
          m.content.callKey == callKey &&
          ids.containsAll(m.content.sourceEventIds) &&
          m.content.sourceEventIds.toSet().length < ids.length)
        m.content.coverageHash,
  };
  if (superseded.length >= maxSupersessions) {
    return const TerminallyIneligible('supersession-cap');
  }

  final mine = h.where((half) => _matchesMe(half, myUserId, myDeviceId));
  if (mine.isEmpty || mine.first.content.handedOverTo != null) {
    return const NotCandidate();
  }

  final candidates = [
    for (final half in h)
      if (half.content.handedOverTo == null)
        _Candidate(half.senderId, half.content.deviceId ?? ''),
  ]..sort(_compareCandidates);
  final myRank = candidates.indexWhere(
    (c) => c.senderId == myUserId && c.deviceId == myDeviceId,
  );

  return Mergeable(
    myRank: myRank,
    coverageEventIds: h.map((half) => half.eventId).toList()..sort(),
    mergedStartSfuMs: closed.startSfuMs,
    trimEndSfuMs: closed.trimEndSfuMs,
  );
}

/// How many merges one call may accumulate before no more are posted: each
/// supersession needs H to have grown, and a speaker's chain is bounded, so
/// this only ever stops a call that is misbehaving.
const maxSupersessions = 8;
