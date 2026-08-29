import 'package:flutter/foundation.dart';

/// One device in the running to record a call, and whether it can.
///
/// Two facts, because ranking on the device id alone hands the recording to
/// whichever device sorts lowest whether or not that device has anywhere to
/// record from — and the learner then talks into a call nobody is transcribing
/// while a perfectly capable phone of theirs sits second in line.
@immutable
class CaptureCandidate {
  /// The device id the SFU carries for it, which is what orders the fleet.
  final String deviceId;

  /// Whether it can record right now, as far as it has told anyone.
  ///
  /// TRUE BY DEFAULT, and the default is load-bearing rather than convenient.
  /// Silence reads as ABLE, so a sibling running an older build, or one whose
  /// announcement has not landed yet, ranks exactly as it did before
  /// capability existed. Reading silence as "cannot" would have every device
  /// out-rank every sibling it had not yet heard from, which during the first
  /// moments of a call is all of them.
  final bool canCapture;

  const CaptureCandidate(this.deviceId, {this.canCapture = true});

  @override
  bool operator ==(Object other) =>
      other is CaptureCandidate &&
      other.deviceId == deviceId &&
      other.canCapture == canCapture;

  @override
  int get hashCode => Object.hash(deviceId, canCapture);

  @override
  String toString() => 'CaptureCandidate($deviceId, canCapture: $canCapture)';
}

/// Decides whether this device is the one that records a call.
///
/// A learner signed in on two devices would otherwise have both record their
/// own microphone, and be credited twice for saying something once.
///
/// The decision is local and needs no agreement. Every device ranks the same
/// candidates the same way and reaches the same verdict without exchanging a
/// message, so there is nothing to negotiate, nothing to confirm, and nothing
/// that can deadlock or flap.
///
/// It is deliberately blunt: device ids carry no meaning, so among devices that
/// can equally record, the winner may be the one the learner has walked away
/// from. That costs a stretch of credit until the other device leaves the call.
/// Losing credit is recoverable and inventing it is not, which is the trade
/// this makes.
class CaptureElection {
  /// This device.
  final String myDeviceId;

  /// The learner's other devices holding a live membership in the same call, as
  /// far as this device can see. May include this device; may be stale; may be
  /// empty because nothing else is there or because nothing else is visible
  /// yet.
  final Iterable<CaptureCandidate> siblings;

  /// Whether this device can record right now.
  ///
  /// Defaults to true for the same reason [CaptureCandidate.canCapture] does,
  /// and so that a caller with nothing to say about capability gets exactly the
  /// ranking this made before capability existed.
  final bool iCanCapture;

  const CaptureElection({
    required this.myDeviceId,
    required this.siblings,
    this.iCanCapture = true,
  });

  /// This device as its siblings rank it.
  CaptureCandidate get _me =>
      CaptureCandidate(myDeviceId, canCapture: iCanCapture);

  /// A TOTAL ORDER: capability first, device id second.
  ///
  /// Capability RANKS, it never vetoes. A fleet where every device has
  /// concluded it cannot record still elects exactly one of them, which then
  /// tries and reports honestly — rather than every device standing aside and
  /// the call going unrecorded because they all agreed they were unable.
  /// Falling through to the device id is what keeps the order total, and a
  /// total order is what lets every device reach the same verdict alone.
  static bool _sortsBefore(CaptureCandidate a, CaptureCandidate b) =>
      a.canCapture != b.canCapture
      ? a.canCapture
      : a.deviceId.compareTo(b.deviceId) < 0;

  /// Whether this device records.
  ///
  /// True when no sibling sorts before it. This device is always part of its
  /// own comparison, so a device that cannot see its own membership — a write
  /// that was lost, a sync that has not caught up — still ranks itself rather
  /// than concluding it is absent and falling silent.
  ///
  /// Among devices that agree on capability, seeing more devices can turn this
  /// false and seeing fewer never can.
  ///
  /// The device-id skip is REDUNDANCY, not a fix: `Room.remoteParticipants` is
  /// a separate collection from `localParticipant`, so our own id does not
  /// appear there, and the caller filters again before it gets here. It stays
  /// because it is the one comparison where a stale capability reading of
  /// OURSELVES could out-rank the live one we hold.
  bool get shouldRecord => !siblings.any(
    (sibling) => sibling.deviceId != myDeviceId && _sortsBefore(sibling, _me),
  );

  /// Which sibling takes the recording when this device does not.
  ///
  /// Ranked by the same total order [shouldRecord] uses, so the device named
  /// here is the device that will actually be recording. Two rankings that
  /// could disagree would have this device discard its tail on the strength of
  /// a successor that never started.
  ///
  /// Null when there is nobody else, which is the case where this device
  /// records or nothing does.
  CaptureCandidate? get recordingSuccessor {
    CaptureCandidate? best;
    for (final sibling in siblings) {
      if (sibling.deviceId == myDeviceId) continue;
      if (best == null || _sortsBefore(sibling, best)) best = sibling;
    }
    return best;
  }

  /// Whether audio captured before a handover has to be thrown away rather than
  /// delivered.
  ///
  /// This is what the convergence race costs if nothing is done about it. Two
  /// of a learner's devices answering the same call in the same instant each
  /// see a roster that momentarily lacks the other, so each elects ITSELF and
  /// starts recording. A moment later both rosters converge, the loser stops —
  /// and delivers the opening seconds that the winner also recorded. The server
  /// keys a result by capture session and chunk index, and two devices produce
  /// two sessions, so nothing downstream absorbs that: the learner is credited
  /// twice for saying something once.
  ///
  /// Three decisions, each of which changes the answer.
  ///
  /// EQUAL JOIN TIMES DISCARD. `Participant.joinedAt` is exposed in whole
  /// SECONDS, so two devices answering the same ring read as having joined at
  /// exactly the same time — which is precisely the reported case. A
  /// strictly-earlier rule would deliver the duplicate this exists to stop.
  ///
  /// A JOIN TIME NOBODY STAMPED IS NOT A JOIN TIME. Either side being unknown
  /// answers false, because discarding a learner's speech on the strength of a
  /// number that was never measured destroys audio no other device holds.
  ///
  /// AND THE SUCCESSOR HAS TO HAVE BEEN RECORDING THE SAME STRETCH. Join times
  /// only establish that it was in the call; [successorRecordedTheSameStretch]
  /// is the caller's statement that it was also able to record throughout, so
  /// that the device id — not capability — is what displaced us, and was what
  /// displaced us for the whole stretch.
  ///
  /// A SPAN, deliberately, and not a reading taken at the handover. A successor
  /// that out-ranked us only because it JUST became able had no tap while we
  /// were recording, and a caller that compared the two capabilities at the
  /// instant of the displacement could not tell that from a device that had
  /// been able all along. Nor is a successor tied with us at "cannot"
  /// recording, which the id also decides between: whichever of them wins is
  /// recording nothing. Either way discarding throws away the only copy of what
  /// the learner said.
  static bool discardsCapturedAudio({
    DateTime? myJoinedAt,
    DateTime? successorJoinedAt,
    required bool successorRecordedTheSameStretch,
  }) {
    if (!successorRecordedTheSameStretch) return false;
    if (myJoinedAt == null || successorJoinedAt == null) return false;
    return !successorJoinedAt.isAfter(myJoinedAt);
  }
}
