import 'package:flutter/foundation.dart';

/// One of this account's devices saying, of itself, that audio is reaching its
/// recorder RIGHT NOW.
///
/// The only currency [CaptureElection.discardsCapturedAudio] accepts as proof
/// that somebody else holds a stretch this device is about to destroy, and the
/// reason it is a type rather than a boolean. A boolean can be assembled out of
/// whatever a caller had to hand — and the bug this replaced was exactly that:
/// a sibling's [CaptureCandidate.canCapture], which is TRUE FOR SILENCE, was
/// read as though the sibling had said it was recording. There is no
/// constructor here that turns confidence into evidence. The only way to hold
/// one is to have read the value a sibling actually published.
@immutable
class CaptureAttestation {
  /// Which device said it.
  ///
  /// Carried so that evidence about one sibling can never license destroying a
  /// stretch a DIFFERENT sibling was supposed to be holding. The discard checks
  /// it rather than trusting the call site to have looked the right device up.
  final String deviceId;

  const CaptureAttestation._(this.deviceId);

  /// The value a device publishes while, and only while, audio is actually
  /// arriving at its recorder.
  static const attested = 'recording';

  /// Minted from what a sibling published, and from nothing else.
  ///
  /// Null for silence, for an older build that publishes nothing, and for a
  /// value from a future version this build does not understand. Every one of
  /// those is an ABSENCE OF EVIDENCE rather than a denial, and the whole point
  /// of this file is that absence never destroys audio.
  ///
  /// The polarity is deliberately the OPPOSITE of the capability attribute next
  /// to it, and the two are not in tension. Capability RANKS, and being wrong
  /// about it costs at most a couple of seconds in which the wrong device holds
  /// the recording, which the next election takes back — so silence there reads
  /// as ABLE and the fleet defers rather than deadlocking. This one AUTHORISES
  /// DESTRUCTION, and being wrong about it costs a thing the learner said that
  /// no device anywhere still holds. Nothing takes that back.
  static CaptureAttestation? of(String deviceId, String? published) =>
      published == attested ? CaptureAttestation._(deviceId) : null;

  @override
  bool operator ==(Object other) =>
      other is CaptureAttestation && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;

  @override
  String toString() => 'CaptureAttestation($deviceId)';
}

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
///
/// THAT TRADE GOVERNS WHO RECORDS, AND NOTHING ELSE. It is safe to make because
/// standing aside is undone by the next election two seconds later: the device
/// is still there, the microphone is still there, and the only thing spent is a
/// stretch of a conversation that is still happening. Nothing in it licenses
/// DESTROYING audio that has already been captured, which no later election
/// undoes and no other copy replaces. The two decisions therefore take opposite
/// defaults, and [discardsCapturedAudio] states the second one: rank
/// optimistically about a sibling, and destroy only on proof.
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
  /// ONE RULE, and every term below is an application of it rather than a
  /// separate judgement call:
  ///
  ///   AUDIO IS DESTROYED ONLY ON POSITIVE EVIDENCE THAT ANOTHER DEVICE HOLDS
  ///   THE SAME STRETCH. Every input has to be something a device affirmatively
  ///   established. The absence of a denial is not evidence, and neither is a
  ///   measurement too coarse to answer the question being asked of it.
  ///
  /// The rule is stated here once and enforced by the SHAPE of the arguments
  /// rather than by each caller remembering it. [successorIsRecording] cannot
  /// be spelled as a boolean somebody was confident about; the only way to hold
  /// a [CaptureAttestation] is to have read the value a sibling published.
  /// [seenNotRecording] is a set of observations rather than a verdict, so a
  /// caller can hand over the wrong facts but not the wrong conclusion. The
  /// version this replaced took a `bool` for the whole question, and the caller
  /// assembled it from the nearest thing to hand that read like an answer.
  ///
  /// FOUR THINGS HAVE TO BE TRUE, and each of them fails CLOSED.
  ///
  /// THE SUCCESSOR HAS TO SAY IT IS RECORDING. Not that it CAN: capability is
  /// true for silence by design, so a sibling whose tap attached and then never
  /// produced a frame goes on advertising "able" until its own watchdog fires
  /// fifteen seconds later — which is the failure the watchdog exists to
  /// detect. Reading that as "it recorded" is how the one captured copy of a
  /// learner's words came to be thrown away by the device that held it.
  ///
  /// THE ATTESTATION HAS TO BE ABOUT THE SUCCESSOR. Checked here rather than
  /// left to the call site, because a lookup against the wrong device id is
  /// exactly the kind of mistake that reads correctly.
  ///
  /// AND IT HAS TO COVER THE WHOLE STRETCH. [seenNotRecording] is every sibling
  /// this device has observed, at any point while this stretch was running,
  /// NOT recording. A successor that only started when it took over holds none
  /// of what came before, whatever it is doing now.
  ///
  /// AND THE JOIN STAMPS HAVE TO ORDER THE TWO DEVICES AT THE RESOLUTION THEY
  /// ACTUALLY CARRY. `Participant.joinedAt` is derived from a whole-SECOND
  /// field, so a stamp of 12:00:00 means "somewhere in the second beginning at
  /// 12:00:00" and two equal stamps order NOTHING. The rule this replaced read
  /// equality as "the successor was here first", so a device that joined at
  /// 12:00:00.001 and recorded until a sibling joined at 12:00:00.900 threw
  /// away nine hundred milliseconds the sibling was not in the room for. Only a
  /// stamp a full resolution step earlier proves the successor was already
  /// there, and a stretch cannot begin before the device recording it joined.
  ///
  /// WHAT THIS GIVES UP, deliberately and with a way back. Two devices that
  /// genuinely answered in the same instant read as equal, and equal no longer
  /// discards — so that race now ends in a delivered duplicate rather than in a
  /// gamble on whether the loser's opening second was the only copy. A
  /// duplicate is a wrong number in a learner's analytics; a discard that
  /// guessed wrong is something the learner said that nothing anywhere still
  /// has. The way back is not a looser rule, it is a better measurement: the
  /// SFU already sends a millisecond join stamp (`ParticipantInfo.joined_at_ms`)
  /// and livekit_client 2.11.0 simply does not expose it. When it does,
  /// [joinStampResolution] drops and the same rule discards the race again.
  ///
  /// Note what is NOT here any more. Whether WE could record, and whether the
  /// successor merely out-ranked us on capability, both used to be terms. An
  /// attestation is strictly stronger than either: a device that is recording
  /// is not a device that lost the tiebreak while recording nothing.
  static bool discardsCapturedAudio({
    required CaptureCandidate successor,
    required CaptureAttestation? successorIsRecording,
    required Set<String> seenNotRecording,
    DateTime? myJoinedAt,
    DateTime? successorJoinedAt,
  }) {
    if (successorIsRecording == null) return false;
    if (successorIsRecording.deviceId != successor.deviceId) return false;
    if (seenNotRecording.contains(successor.deviceId)) return false;
    if (myJoinedAt == null || successorJoinedAt == null) return false;
    return !successorJoinedAt.add(joinStampResolution).isAfter(myJoinedAt);
  }

  /// The resolution the join stamps this compares are actually measured at.
  ///
  /// livekit_client builds `Participant.joinedAt` by multiplying a whole-second
  /// protocol field by a thousand, so the milliseconds it appears to carry are
  /// always zero and a stamp names a one-second window rather than an instant.
  /// Widening a comparison by the resolution of its inputs is the whole
  /// mechanism: it is what makes "the successor was already here" a fact rather
  /// than a coin toss.
  ///
  /// Shrinking this is SAFE in the direction that matters and only ever gets
  /// more discards right, but it must not be shrunk below what the source
  /// actually measures. Too large refuses a discard that was sound; too small
  /// destroys audio on an ordering nobody established.
  static const joinStampResolution = Duration(seconds: 1);
}
