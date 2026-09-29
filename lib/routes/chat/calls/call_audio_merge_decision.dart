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

/// A `pangea.call_audio_merged` event for this call already exists.
///
/// Retire: remove any durable index entry for this call and do nothing more.
/// Checked FIRST, ahead of every other question, because an already-merged
/// call is done regardless of what its halves currently look like.
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
/// - `'more-than-two-halves'` -- more than two `pangea.call_audio` events
///   were found for this call (a mid-call device switch; v2).
/// - `'user-with-multiple-halves'` -- two halves share a sender, meaning that
///   user recorded from more than one tenure during the call (also a device
///   switch, v2). This is the same underlying condition as
///   `'more-than-two-halves'` when there are exactly two halves from one
///   sender; it is reported under this reason rather than that one because
///   the halves-count check runs first and passes for exactly two.
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

  const Mergeable({
    required this.myRank,
    required this.coverageEventIds,
    required this.mergedStartSfuMs,
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
/// halves -- PURELY, from exactly the four inputs given. No I/O, no Matrix
/// client, no `DateTime.now()`: every branch below is a fact about [halves],
/// [isDmRoom], [myUserId], [myDeviceId], and [mergedExists] alone, which is
/// what makes every verdict unit-testable and mutation-provable without a
/// homeserver.
///
/// [halves] -- every `pangea.call_audio` half found for this call (from
/// `fetchCallAudio`), in whatever order the caller fetched them; this
/// function does not depend on that order.
/// [isDmRoom] -- whether the room is a 1:1 DM. `true`/`false` when known,
/// `null` when not yet known (room state may still be loading) -- `null` is
/// NOT the same as `false` and must never be treated as one.
/// [myUserId] -- this device's own Matrix user id.
/// [myDeviceId] -- this device's own device id, or null if this device does
/// not know it yet.
/// [mergedExists] -- whether a `pangea.call_audio_merged` event for this call
/// has already been found.
///
/// The checks below run in EXACTLY this order, and the order is load-bearing
/// -- a later check's precondition depends on every earlier one having
/// already been ruled out, so reordering them changes what gets decided, not
/// just how fast:
/// 1. [mergedExists] -> [AlreadyMerged].
/// 2. `isDmRoom == false` -> [TerminallyIneligible] (`'not-a-dm'`).
/// 3. `isDmRoom == null` -> [PendingIncomplete] (DM-ness not yet known).
/// 4. More than two halves -> [TerminallyIneligible]
///    (`'more-than-two-halves'`).
/// 5. Two halves share a sender -> [TerminallyIneligible]
///    (`'user-with-multiple-halves'`); this also covers the 2-halves,
///    1-sender case.
/// 6. Fewer than two halves -> [PendingIncomplete] (the peer's half has not
///    arrived).
/// 7. Either of the (now exactly two, two-distinct-sender) halves is not
///    placeable -> [TerminallyIneligible] (`'unplaceable-half'`).
/// 8. Neither half was posted by this device -> [NotCandidate].
/// 9. This device posted one of the two halves -> [Mergeable].
CallAudioMergeVerdict decideCallAudioMerge({
  required List<CallAudioRecording> halves,
  required bool? isDmRoom,
  required String myUserId,
  required String? myDeviceId,
  required bool mergedExists,
}) {
  // 1. A merged event already exists: nothing left to decide.
  if (mergedExists) return const AlreadyMerged();

  // 2. Explicitly known to be a non-DM (group) room: out of v1 scope, and
  // that fact can never change for this call.
  if (isDmRoom == false) return const TerminallyIneligible('not-a-dm');

  // 3. DM-ness is not yet known. This is NOT terminal -- room state may still
  // be loading, and a later trigger may find it a DM.
  if (isDmRoom == null) return const PendingIncomplete();

  // Room is confirmed a DM from here on.

  // 4. A third (or later) half means a mid-call device switch, which this
  // decision core never merges (v2 scope).
  if (halves.length > 2) {
    return const TerminallyIneligible('more-than-two-halves');
  }

  // 5. Two halves from the SAME sender means that user has more than one
  // tenure of the recording -- a device switch, same as check 4 but caught
  // here because the half count alone (<=2) did not already catch it. This
  // also covers the case of exactly two halves both from one sender.
  final distinctSenders = halves.map((h) => h.senderId).toSet();
  if (distinctSenders.length < halves.length) {
    return const TerminallyIneligible('user-with-multiple-halves');
  }

  // 6. Fewer than two halves: the peer's half has not shown up yet. Not
  // terminal -- it may still arrive.
  if (halves.length < 2) return const PendingIncomplete();

  // From here: EXACTLY two halves, from two DISTINCT senders -- the DM's two
  // members, derived from the halves themselves rather than from room
  // membership or `callPeerOf`.

  // 7. Both halves must be placeable, or this call can never produce a clean
  // merged file.
  if (halves.any((h) => !_isPlaceable(h))) {
    return const TerminallyIneligible('unplaceable-half');
  }

  // 8. Is this device one of the two posters?
  if (!halves.any((h) => _matchesMe(h, myUserId, myDeviceId))) {
    return const NotCandidate();
  }

  // 9. This device posted one of the two halves. Rank the two `(senderId,
  // deviceId)` candidates deterministically, sort the coverage, and take the
  // earlier start.
  final candidates =
      halves
          .map((h) => _Candidate(h.senderId, h.content.deviceId ?? ''))
          .toList()
        ..sort(_compareCandidates);

  // myDeviceId is guaranteed non-null here: check 8 only matched if
  // myDeviceId != null, so this candidate's own key was never substituted.
  final myRank = candidates.indexWhere(
    (c) => c.senderId == myUserId && c.deviceId == myDeviceId,
  );

  final coverageEventIds = halves.map((h) => h.eventId).toList()..sort();

  final mergedStartSfuMs = halves
      .map((h) => h.content.fileStartSfuMs!)
      .reduce((a, b) => a < b ? a : b);

  return Mergeable(
    myRank: myRank,
    coverageEventIds: coverageEventIds,
    mergedStartSfuMs: mergedStartSfuMs,
  );
}
