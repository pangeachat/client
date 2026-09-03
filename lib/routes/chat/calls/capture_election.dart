import 'package:flutter/foundation.dart';

import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

/// What one of this account's devices has said about whether it is recording.
///
/// THREE states, and the third one is the whole point. A device can be SILENT,
/// it can DENY that it is recording, and it can ATTEST that it is — and silence
/// is not a denial. Collapsing the two is what the first version of this did,
/// in both directions and with a bug at each end: a sibling that had said
/// nothing was read as recording, and later, a sibling that had said nothing
/// was read as NOT recording and disqualified for the rest of a stretch it was
/// actually holding.
///
/// Silence really does mean nothing here. An older build publishes none of
/// this; a device whose write is still on the wire has published none of it
/// YET; a value from a future version is not a sentence this build can read.
/// None of those is a fact about what the device is doing, and neither
/// destroying audio nor keeping a duplicate may rest on one.
///
/// [run] is what makes the attestation a claim about a SPAN rather than an
/// instant. It names the uninterrupted stretch of captured audio the device is
/// in the middle of, and it changes whenever that stretch breaks — so a watcher
/// that saw `recording:4` before and `recording:5` now knows a gap happened
/// even though the `no` between them never reached it. Attribute writes are
/// last-write-wins and an observer sees only the latest, so without the token a
/// stop and restart is INVISIBLE, and the audio in the gap belongs to nobody.
@immutable
class CaptureReport {
  /// Which device this is about.
  ///
  /// Carried so that evidence about one sibling can never license destroying a
  /// stretch a DIFFERENT sibling was supposed to be holding. The discard checks
  /// it rather than trusting the call site to have looked the right device up.
  final String deviceId;

  /// The uninterrupted stretch of captured audio it says it is in the middle
  /// of, or null when it is not saying that.
  final String? run;

  /// Whether it has EXPLICITLY said it is not recording, as opposed to having
  /// said nothing.
  final bool denies;

  const CaptureReport._(this.deviceId, {this.run, this.denies = false});

  static const _notRecording = 'no';
  static const _runPrefix = 'recording:';

  /// The value a device publishes to say what it is doing.
  ///
  /// A device in a call publishes this even while it is NOT recording, which
  /// is the difference between a denial and a silence and therefore the only
  /// reason a watcher can tell an idle sibling from one it has not heard from.
  /// It costs one write per device per call.
  static String published(String? run) =>
      run == null ? _notRecording : '$_runPrefix$run';

  /// Read back from what a sibling published, and from nothing else.
  ///
  /// There is no constructor here that turns confidence into an attestation.
  /// The only way to hold one is to have read an affirmative value a sibling
  /// actually wrote, which is what stops a caller assembling the answer out of
  /// whatever it had to hand — the shape of the original bug.
  ///
  /// The polarity is deliberately the opposite of the capability attribute this
  /// sits beside, and the two are not in tension. Capability RANKS, and being
  /// wrong about it costs at most a couple of seconds in which the wrong device
  /// holds the recording, which the next election takes back — so silence there
  /// reads as ABLE and the fleet defers rather than deadlocking. This one
  /// AUTHORISES DESTRUCTION, and silence buys nothing at all.
  factory CaptureReport.of(String deviceId, String? published) {
    if (published == _notRecording) {
      return CaptureReport._(deviceId, denies: true);
    }
    if (published != null && published.startsWith(_runPrefix)) {
      final run = published.substring(_runPrefix.length);
      if (run.isNotEmpty) return CaptureReport._(deviceId, run: run);
    }
    // Absent, empty, or a sentence from a build this one does not speak. Silent
    // rather than denying: a value we cannot read is not a device telling us it
    // has stopped, and treating it as one would disqualify a sibling that is
    // recording perfectly well.
    return CaptureReport._(deviceId);
  }

  @override
  bool operator ==(Object other) =>
      other is CaptureReport &&
      other.deviceId == deviceId &&
      other.run == run &&
      other.denies == denies;

  @override
  int get hashCode => Object.hash(deviceId, run, denies);

  @override
  String toString() =>
      'CaptureReport($deviceId, ${run == null ? (denies ? 'not recording' : 'silent') : 'recording $run'})';
}

/// What this device has watched its siblings do while IT was recording.
///
/// The discard asks whether a successor held the whole stretch about to be
/// destroyed, and one reading answers only for the instant it was taken. This
/// is the ledger that turns a sequence of instants into a statement about the
/// span — and, just as importantly, the place that decides what counts as
/// holding it, so no call site has to.
///
/// TWO THINGS, and the first is the one that is easy to leave out. A run has to
/// have been ALREADY RUNNING when this stretch opened, and it has to have gone
/// unbroken since. A run token proves continuity forward from the moment it was
/// first seen and says nothing whatever about the time before that — so a
/// sibling first seen recording halfway through holds only the half it was seen
/// for, and crediting it destroys the other half. The opening snapshot is
/// therefore the only place a sibling can be credited at all.
///
/// A sibling that is silent or denying at the opening is simply NOT CREDITED.
/// That is not the same as being marked broken: silence still settles nothing,
/// and a sibling that goes quiet later — a dropped attribute update, a write
/// that failed — keeps the standing it opened with. The difference matters,
/// because latching silence into a permanent denial once kept duplicates of
/// stretches a sibling really held.
///
/// What it CANNOT see is a sibling that was not in the roster at the opening.
/// Such a sibling is not credited either, for exactly the same reason, and that
/// is the honest answer rather than a gap: nothing this device observed says
/// anything about what that sibling was doing while it could not see it.
class CaptureWatch {
  /// The run each sibling was ALREADY IN when this stretch opened. A sibling
  /// absent from here was never in a position to hold this stretch.
  final Map<String, String> _openedIn = {};

  /// Credited siblings that have since been seen to break.
  final Set<String> _interrupted = {};

  /// Whether the opening snapshot has been taken.
  bool _opened = false;

  /// Starts a fresh stretch. Everything watched during the previous one says
  /// nothing about this one.
  void restart() {
    _openedIn.clear();
    _interrupted.clear();
    _opened = false;
  }

  /// Takes ONE snapshot of every sibling.
  ///
  /// A whole snapshot rather than a reading at a time, because "was it already
  /// running when this stretch opened" is a question about the FIRST snapshot,
  /// and a per-sibling call cannot tell the first reading of the STRETCH from
  /// the first reading of that SIBLING. The two differ for every sibling that
  /// appears late, which is the entire population this has to be careful about.
  void observe(Iterable<CaptureReport> snapshot) {
    if (!_opened) {
      _opened = true;
      for (final report in snapshot) {
        final run = report.run;
        // Only a sibling already recording when we started can hold what we
        // are about to destroy. Silence and denial alike leave it uncredited.
        if (run != null) _openedIn[report.deviceId] = run;
      }
      return;
    }
    for (final report in snapshot) {
      final opened = _openedIn[report.deviceId];
      // Nothing to break. A sibling that was never credited cannot lose
      // standing it never had.
      if (opened == null) continue;
      if (report.denies) {
        _interrupted.add(report.deviceId);
      } else if (report.run != null && report.run != opened) {
        // It stopped and started again. The `no` in between may never have
        // reached us — attributes are last-write-wins — so the token is the
        // only evidence the gap happened, and the audio in it belongs to
        // nobody.
        _interrupted.add(report.deviceId);
      }
      // Silence changes nothing. We have simply not heard from it since.
    }
  }

  /// Whether the sibling was recording [run] when this stretch opened and has
  /// not been seen to break since.
  bool heldThroughout(String deviceId, String run) =>
      _openedIn[deviceId] == run && !_interrupted.contains(deviceId);
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
  ///   established. The absence of a denial is not evidence, the absence of an
  ///   attestation is not evidence either, and neither is a measurement too
  ///   coarse to answer the question being asked of it.
  ///
  /// The middle clause is the one that took two goes to get right, because it
  /// cuts BOTH ways and each direction has its own bug. Reading silence as "it
  /// recorded" throws away the only copy. Reading silence as "it did not
  /// record" — and remembering that for the rest of a stretch — keeps a
  /// duplicate of audio a sibling really was holding. Neither is a reading;
  /// they are two ways of inventing one. Silence is handled by having devices
  /// SAY they are not recording, so an idle sibling is a denial and only a
  /// sibling we have genuinely not heard from is silent.
  ///
  /// The rule is stated here once and enforced by the SHAPE of the arguments
  /// rather than by each caller remembering it. [successorReport] cannot be
  /// spelled as a boolean somebody was confident about; the only way to hold an
  /// attesting one is to have read the value a sibling published. [watch] is
  /// fed raw readings and decides for itself what breaks a span, so a caller
  /// can hand over the wrong facts but not the wrong conclusion. The version
  /// this replaced took a `bool` for the whole question, and the caller
  /// assembled it from the nearest thing to hand that read like an answer.
  ///
  /// FOUR THINGS HAVE TO BE TRUE, and each of them fails CLOSED.
  ///
  /// THE SUCCESSOR HAS TO BE ATTESTING, IN A NAMED RUN. Not that it CAN
  /// record: capability is true for silence by design, so a sibling whose tap
  /// attached and then never produced a frame goes on advertising "able" until
  /// its own watchdog fires fifteen seconds later — which is the failure the
  /// watchdog exists to detect. And not a bare "yes" either: the run token is
  /// what lets [watch] see a stop-and-restart that last-write-wins attributes
  /// would otherwise hide completely.
  ///
  /// THE REPORT HAS TO BE ABOUT THE SUCCESSOR. Checked here rather than left to
  /// the call site, because a lookup against the wrong device id is exactly the
  /// kind of mistake that reads correctly.
  ///
  /// AND THAT RUN HAS TO HAVE BEEN ALREADY RUNNING WHEN OUR STRETCH OPENED,
  /// AND UNBROKEN SINCE. This is the term that a run token alone does not
  /// supply, and leaving it out is how a stretch came to be destroyed that
  /// covered time the successor demonstrably did not hold. A token proves
  /// continuity FORWARD from the moment it was first seen; it says nothing at
  /// all about the time before that. A successor first seen recording halfway
  /// through our stretch holds the second half, and destroying the whole tail
  /// destroys the first half along with it. So the credit is granted only by
  /// the OPENING snapshot, and [CaptureWatch] is where that lives.
  ///
  /// The join stamp does not stand in for this, and reading it as though it did
  /// was the mistake. It says the successor was in the ROOM before us. Being in
  /// the room is not holding a copy: a device can sit in a call for a minute
  /// before its first frame arrives.
  ///
  /// AND THE JOIN STAMPS HAVE TO ORDER THE TWO DEVICES AT THE RESOLUTION THEY
  /// ACTUALLY CARRY. A stamp of 12:00:00 read off a whole-SECOND field means
  /// "somewhere in the second beginning at 12:00:00", and two equal stamps
  /// order NOTHING. The rule this replaced read equality as "the successor was
  /// here first", so a device that joined at 12:00:00.001 and recorded until a
  /// sibling joined at 12:00:00.900 threw away nine hundred milliseconds the
  /// sibling was not in the room for. Only a stamp a full resolution step
  /// earlier proves the successor was already there, and a stretch cannot begin
  /// before the device recording it joined.
  ///
  /// WHICH RESOLUTION IS A QUESTION ABOUT THE PAIR IN HAND. `Participant.
  /// joinedAt` is derived from a whole-second field, but the SFU also sends the
  /// same instant to the millisecond, and this device now holds that reading
  /// for every participant the SFU named — so [mySfuStamps] and
  /// [successorSfuStamps] travel beside the coarse readings and
  /// [_joinOrdering] decides, from the two stamps themselves, which pair is
  /// being compared and therefore which of [joinStampResolution] and
  /// [millisecondJoinStampResolution] applies. A pair where either half lacks
  /// a millisecond reading is compared at the second, whatever the other half
  /// carries.
  ///
  /// FACTS, NOT A CONCLUSION, in the same sense as every other argument here.
  /// The stamps arrive exactly as the SFU stated them, zeros and all; whether
  /// a zero means "the server said nothing" is decided in [_millisecondJoin]
  /// rather than at the call site, because a caller that judged them first
  /// would be a second place able to authorise a discard.
  ///
  /// WHAT THIS COSTS, because it is a real narrowing. A discard now needs this
  /// device to have WATCHED the successor recording, from its own first frame
  /// onwards. A successor that was merely present, or that this device could
  /// not see for part of the stretch, or whose run this device only heard about
  /// halfway through, keeps its tail delivered — a duplicate. That is the
  /// intended direction: a duplicate is a wrong number in a learner's
  /// analytics, and a discard that guessed wrong is a thing the learner said
  /// that nothing anywhere still holds.
  ///
  /// It is also the only direction available. Proving a successor's run began
  /// before our stretch, without having seen it, needs the two devices to order
  /// events against a shared reference, and they have none: a device can
  /// publish when its run began only on its own clock, and every bound that
  /// crosses the gap between two devices runs the wrong way — the available
  /// evidence can show that a sibling started too LATE, never that it started
  /// early enough. So the opening snapshot is not a conservative approximation
  /// of the answer, it IS the answer.
  ///
  /// WHAT THIS STILL CANNOT DO, stated rather than papered over. Every reading
  /// here is of a snapshot the SFU sent at some earlier, unknowable instant, so
  /// a successor that stopped moments ago can still be showing as attesting.
  /// Audio captured inside that window is destroyed on evidence that was true
  /// when it was published and false by the time it was read. No
  /// publish-and-observe scheme closes it: a device cannot learn another
  /// device's PRESENT state, only what it published at some point in the past,
  /// and LiveKit exposes no server sequence or timestamp against which a
  /// snapshot could be called current. What narrows it is the publishing
  /// discipline on the other side — an attestation is asserted only after audio
  /// has actually flowed, and retracted the moment stopping is INTENDED, in the
  /// first write to leave after that decision. The residue is the signal delay
  /// itself.
  ///
  /// Note what is NOT here any more. Whether WE could record, and whether the
  /// successor merely out-ranked us on capability, both used to be terms. An
  /// attestation is strictly stronger than either: a device that is recording
  /// is not a device that lost the tiebreak while recording nothing.
  static bool discardsCapturedAudio({
    required CaptureCandidate successor,
    required CaptureReport successorReport,
    required CaptureWatch watch,
    DateTime? myJoinedAt,
    DateTime? successorJoinedAt,
    ({int secondsMs, int ms})? mySfuStamps,
    ({int secondsMs, int ms})? successorSfuStamps,
  }) {
    if (successorReport.deviceId != successor.deviceId) return false;
    final run = successorReport.run;
    if (run == null) return false;
    if (!watch.heldThroughout(successor.deviceId, run)) return false;
    final ordering = _joinOrdering(
      myJoinedAt: myJoinedAt,
      successorJoinedAt: successorJoinedAt,
      mySfuStamps: mySfuStamps,
      successorSfuStamps: successorSfuStamps,
    );
    if (ordering == null) return false;
    return !ordering.successor.add(ordering.resolution).isAfter(ordering.mine);
  }

  /// The two joins to order, and the resolution they are ordered at — or null
  /// when this pair orders nothing.
  ///
  /// ONE PLACE PICKS BOTH HALVES, and that is the whole reason this is a
  /// function rather than four arguments resolved at the comparison. A
  /// millisecond stamp for one device against `Participant.joinedAt` for the
  /// other is not a finer comparison, it is a comparison of two different
  /// MEASUREMENTS: the coarse half names a one-second window and the fine half
  /// names an instant inside one, so a mixed pair can read as ordered when the
  /// two joins fell in the same second. Returning both halves together makes
  /// that mixture unrepresentable rather than merely discouraged.
  ///
  /// THE FINE PAIR OR NEITHER. Both stamps come from `CallMedia`'s store, which
  /// holds what the SFU said about each identity exactly as it said it; the
  /// coarse pair comes from the roster's reading of the participant. A pair is
  /// taken whole from one of those two, never assembled across them, so the
  /// KNOWN LIMIT on `CallMedia.recordJoinStamps` — that its statements and the
  /// roster's can describe different frames when an update arrives out of order
  /// — never becomes a term in this comparison.
  ///
  /// The fallback is not a degraded version of the fine answer, it is the
  /// answer this rule gave before a sibling's millisecond stamp was readable at
  /// all. A mixed-version call — livekit-server has only sent `joined_at_ms`
  /// since v1.8.4 — falls here, and so does one where the SFU named a device
  /// the store never heard of. That is a REFUSAL to narrow, and refusing costs
  /// a duplicate.
  static ({DateTime mine, DateTime successor, Duration resolution})?
  _joinOrdering({
    required DateTime? myJoinedAt,
    required DateTime? successorJoinedAt,
    required ({int secondsMs, int ms})? mySfuStamps,
    required ({int secondsMs, int ms})? successorSfuStamps,
  }) {
    final mineMs = _millisecondJoin(mySfuStamps);
    final successorMs = _millisecondJoin(successorSfuStamps);
    if (mineMs != null && successorMs != null) {
      return (
        mine: DateTime.fromMillisecondsSinceEpoch(mineMs),
        successor: DateTime.fromMillisecondsSinceEpoch(successorMs),
        resolution: millisecondJoinStampResolution,
      );
    }
    if (myJoinedAt == null || successorJoinedAt == null) return null;
    return (
      mine: myJoinedAt,
      successor: successorJoinedAt,
      resolution: joinStampResolution,
    );
  }

  /// One device's join to the millisecond, or null when what the SFU said about
  /// it does not carry one.
  ///
  /// [ClockAnchor.millisecondRefinement] is the whole of the wire rule and is
  /// deliberately not restated here: the transcript's clock anchor asks the
  /// same question of the same two proto fields, and a second copy of the
  /// window would be a second thing to get wrong. Absence is INSIDE that rule
  /// rather than beside it — proto3 puts nothing on the wire for an unset field
  /// 17, so a server that never set it and one that set it to zero arrive
  /// identically, and zero fails the window whenever the coarse half is a real
  /// time. There is no "was the field present" flag to consult and none to
  /// invent.
  ///
  /// The ceiling is the one term added here, and it is added for the reason
  /// `CallRoster.usableJoinTime` gives for applying it to the coarse reading: a
  /// number this app would not believe about a clock is not a number the
  /// election may displace a recording over. Without it a stamp naming the year
  /// 5000 would be refused as a join time by the roster and accepted as one
  /// here, and the fine path would destroy audio on a reading the coarse path
  /// threw away.
  static int? _millisecondJoin(({int secondsMs, int ms})? stamps) {
    if (stamps == null) return null;
    final ms = ClockAnchor.millisecondRefinement(stamps.secondsMs, stamps.ms);
    if (ms == null || ms >= ClockAnchor.clockCeilingMs) return null;
    return ms;
  }

  /// The resolution a pair of join stamps is compared at when only the COARSE
  /// reading is available for them — which is the fallback, not the only value.
  ///
  /// livekit_client builds `Participant.joinedAt` by multiplying a whole-second
  /// protocol field by a thousand, so the milliseconds it appears to carry are
  /// always zero and a stamp names a one-second window rather than an instant.
  /// Widening a comparison by the resolution of its inputs is the whole
  /// mechanism: it is what makes "the successor was already here" a fact rather
  /// than a coin toss.
  ///
  /// Neither value may be shrunk below what its own source measures. Too large
  /// refuses a discard that was sound; too small destroys audio on an ordering
  /// nobody established.
  static const joinStampResolution = Duration(seconds: 1);

  /// The resolution a pair is compared at when BOTH stamps are
  /// millisecond-real, which is the finest either source measures.
  ///
  /// A QUESTION ABOUT THE PAIR, never about the call or the deployment, and
  /// that is the part worth being exact about. The SFU sends the join twice —
  /// `joined_at` in whole seconds, and `joined_at_ms` since livekit-server
  /// v1.8.4 — so whether a device's join is known to the millisecond is a fact
  /// about the frame that named THAT device. Two devices in one call can be
  /// named by servers of different versions, and a mixed pair falls back to
  /// [joinStampResolution] rather than assuming the half it cannot see.
  ///
  /// At this resolution the comparison reduces to a strict inequality: a
  /// successor stamped in the same millisecond as us orders nothing and keeps
  /// our tail, exactly as one stamped in the same second did before.
  ///
  /// It only ever gets more discards right, and the reason is arithmetic rather
  /// than optimism. A pair the coarse rule discarded on has the successor's
  /// whole second ending before ours begins, so its millisecond reading is
  /// strictly earlier too and this rule discards on it as well. Narrowing
  /// therefore adds discards and removes none — and every one it adds is a pair
  /// whose order the SFU's own clock states outright.
  static const millisecondJoinStampResolution = Duration(milliseconds: 1);
}
