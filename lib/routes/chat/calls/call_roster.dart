import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' show Logs;

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/calls/call_ownership.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/capture_election.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

/// One participant in a call, as the SFU names them.
///
/// The token service mints a LiveKit identity of `@user:server:DEVICEID` — the
/// same convention Element Call uses — so the identity carries both who is in
/// the call and which of their devices. Everything the call lifecycle needs to
/// know about who is present is derivable from it.
@immutable
class CallParticipant {
  /// The identity string the SFU named them by, kept rather than rebuilt.
  ///
  /// [userId] and [deviceId] are what this class parsed OUT of it, and every
  /// reader that needs the whole string back — `CallMedia`'s join-stamp store
  /// is keyed by it — has to be handed the original. Reassembling
  /// `'$userId:$deviceId'` at a call site would put a second copy of the
  /// splitting rules there, in a place where getting them wrong reads
  /// perfectly: the ambiguous cases [parse] exists for are exactly the ones a
  /// rebuilt string gets right by accident until the day a homeserver carries
  /// a port.
  final String identity;

  final String userId;

  /// Null when the identity carries no device segment. Treated as a distinct
  /// device rather than as this one, so an unparseable identity can never be
  /// mistaken for our own membership.
  final String? deviceId;

  /// When the SFU saw them join, or null when nothing usable was stamped.
  ///
  /// DELIBERATELY OUT OF [==], along with [canCapture] and [capturing].
  /// Presence dedups
  /// participants by set equality, and a field that moves while the same people
  /// are in the same call would make every read of the list a change. What
  /// reads these is [CallRoster]'s own picture, through [state].
  final DateTime? joinedAt;

  /// Whether that device says it can record right now.
  ///
  /// True until it says otherwise. Silence has to read as ABLE: a sibling
  /// running an older build, or one whose announcement has not landed yet,
  /// must rank exactly as it did before capability existed.
  final bool canCapture;

  /// What that device has said about whether it is recording, in the three
  /// states it can say it in.
  ///
  /// Silent by default — the opposite polarity from [canCapture] beside it,
  /// because the two answer different questions. [canCapture] ranks a fleet and
  /// has to defer to a sibling it has not heard from; this one is the only
  /// thing that ever authorises throwing captured audio away, and there silence
  /// has to buy nothing in EITHER direction.
  ///
  /// Out of [==] for the same reason [joinedAt] is: presence dedups by set
  /// equality and this moves while the same people are in the same call.
  /// [state] is what carries it to the notify predicate.
  final CaptureReport? capturing;

  /// What that device has published about being the one carrying on with the
  /// call, in the three states it can say it in.
  ///
  /// Silent by default, like [capturing]: a device that has published no
  /// `pangea_chosen` at all does not speak the ownership protocol — an older
  /// build, or a write still on the wire — and that silence is the whole
  /// discriminator, so it may never be assumed to mean anything. Out of [==]
  /// and carried to the notify predicate through [state], for the reasons
  /// [capturing] gives.
  final ChosenState chosen;

  const CallParticipant({
    required this.identity,
    required this.userId,
    this.deviceId,
    this.joinedAt,
    this.canCapture = true,
    this.capturing,
    this.chosen = ChosenState.silent,
  });

  /// Splits a `@user:server:DEVICE` identity.
  ///
  /// [myUserId], when given, settles an ambiguity that cannot be settled by
  /// looking at the string: a homeserver may carry a port, so `@u:host:8448` is
  /// both a plausible bare user id and a plausible user-plus-device. Matching
  /// this account's own id first means our own devices are never misread as
  /// somebody else — which would have told a caller their call was answered
  /// when the only other participant was themselves.
  factory CallParticipant.parse(String identity, {String? myUserId}) {
    if (myUserId != null && myUserId.isNotEmpty) {
      if (identity == myUserId) {
        return CallParticipant(identity: identity, userId: myUserId);
      }
      if (identity.startsWith('$myUserId:')) {
        final rest = identity.substring(myUserId.length + 1);
        // Only when what follows is a single segment. Another user whose id
        // extends ours — ours with a port, say — would otherwise be read as one
        // of our own devices, and a real peer would not count as present.
        if (!rest.contains(':')) {
          return CallParticipant(
            identity: identity,
            userId: myUserId,
            deviceId: rest,
          );
        }
      }
    }
    // Someone else. The last segment is taken as their device, which is what
    // the token service always appends.
    final split = identity.lastIndexOf(':');
    if (split <= 0 ||
        !identity.startsWith('@') ||
        identity.indexOf(':') == split) {
      return CallParticipant(identity: identity, userId: identity);
    }
    return CallParticipant(
      identity: identity,
      userId: identity.substring(0, split),
      deviceId: identity.substring(split + 1),
    );
  }

  /// The same participant carrying what the SFU says ABOUT them.
  ///
  /// Separate from [CallParticipant.parse] so the identity rules above — which
  /// took two bug reports to get right — stay one piece of code with one set of
  /// return paths.
  CallParticipant describedBy({
    DateTime? joinedAt,
    bool canCapture = true,
    CaptureReport? capturing,
    ChosenState chosen = ChosenState.silent,
  }) => CallParticipant(
    identity: identity,
    userId: userId,
    deviceId: deviceId,
    joinedAt: joinedAt,
    canCapture: canCapture,
    capturing: capturing,
    chosen: chosen,
  );

  /// Everything about this participant that anyone downstream reads, INCLUDING
  /// the three fields [==] leaves out.
  ///
  /// A record, so comparing two of them compares every field structurally. This
  /// is what the roster's notify predicate is built from: a hand-maintained
  /// list of "fields worth notifying about" is how a capability change came to
  /// land in silence.
  (String, String, String?, DateTime?, bool, CaptureReport?, ChosenState)
  get state =>
      (identity, userId, deviceId, joinedAt, canCapture, capturing, chosen);

  @override
  bool operator ==(Object other) =>
      other is CallParticipant &&
      other.userId == userId &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(userId, deviceId);

  @override
  String toString() => 'CallParticipant($userId, $deviceId)';
}

/// One participant exactly as the SFU currently describes them, before any of
/// it is believed.
///
/// The raw facts travel rather than a tidied-up conclusion, because the tidying
/// is the part that has to be tested: [CallRoster.usableJoinTime] is the rule
/// that decides which join stamps mean anything, and a seam that applied it
/// before handing the value over would leave a fake roster unable to stand up
/// the cases the rule exists for.
@immutable
class RosterMember {
  final String identity;
  final int audioPublications;
  final int mutedAudioPublications;

  /// Whether the SFU has actually described this participant yet.
  ///
  /// livekit_client's `Participant.joinedAt` is NON-NULLABLE, and when it has
  /// no server-side info to read it returns `DateTime.timestamp()` — a fresh
  /// read of THIS device's clock, which is not a join time at all and is a
  /// different value every time it is asked. So "described" has to travel
  /// beside the stamp; without it there is no branch in which a join time can
  /// be unknown, and the picture below would differ on every recompute.
  final bool described;

  /// The join time the SDK hands over, believed only when [described].
  final DateTime joinedAt;

  /// The participant's published attributes, which is how a sibling says
  /// whether it can record.
  final Map<String, String> attributes;

  const RosterMember({
    required this.identity,
    required this.described,
    required this.joinedAt,
    this.audioPublications = 0,
    this.mutedAudioPublications = 0,
    this.attributes = const {},
  });
}

/// ONE snapshot of everything the call lifecycle reads off the SFU.
///
/// Taken once per recompute and read many times, so presence, the mute
/// indicator and the recorder election cannot disagree about what they saw. It
/// is also the single surface a test overrides: a fake that supplied identities
/// through one seam and join times through another could be made to describe a
/// room the real one can never be in.
@immutable
class RosterRead {
  /// Everyone else in the room, whichever account they belong to.
  final List<RosterMember> remotes;

  /// This device's own membership, or null before the SFU has given us one.
  final RosterMember? me;

  const RosterRead({required this.remotes, this.me});
}

/// Who is in the call right now, according to the SFU.
///
/// **Read as state, never accumulated from events.** A participant who was
/// already in the room when this device joined is added by the SDK's
/// join-response handler before its update pass runs, so no
/// `ParticipantConnectedEvent` is emitted for them — and events raised before
/// the connection completes are dropped outright. Building presence from those
/// events would therefore miss the peer in the one case that matters most: the
/// person answering a call always joins a room the caller is already in.
///
/// So this recomputes the whole picture from the SFU's participant list on
/// every notification. Level-triggered, which also makes it self-healing: a
/// missed notification costs nothing, because the next one restates the truth
/// rather than adding to a tally that has drifted.
///
/// This is the single source of truth for who is in a call. The recorder
/// election reads it too — an election that disagreed with presence about who
/// is present would hand a recording to a device that had left.
class CallRoster extends ChangeNotifier {
  final String myUserId;

  /// What this call's token said about publishing attributes, as read when it
  /// was issued.
  ///
  /// Carried here so that a failed write can be told apart from an outage. From
  /// inside [_write] the two are the same thrown error, and only one of them is
  /// a deployment we have to change — which is exactly why the refusal read as
  /// an ordinary flake for the life of the feature.
  ///
  /// NOTHING RANKS ON IT. The election reads what has actually been announced
  /// ([announcedCanCapture]), and that stays the right input: a token WITH the
  /// grant can still fail to write, so the observed failure is strictly better
  /// evidence than the predicted one. This is here to say WHY, not to change
  /// what anyone decides.
  final MetadataGrant metadataGrant;

  final lk.Room _room;

  /// The attribute a device publishes to tell its siblings whether it can
  /// record, and the two values it takes.
  ///
  /// A value rather than the key's presence, because attributes are merged
  /// rather than replaced and there is no clean way to take a key back.
  static const canCaptureAttribute = 'pangea_can_capture';
  static const _canRecord = 'yes';
  static const _cannotRecord = 'no';

  /// The attribute a device publishes to say whether audio is ACTUALLY reaching
  /// its recorder, and which uninterrupted stretch of it is running.
  ///
  /// A SECOND attribute rather than a richer value in the first one, because
  /// the two mean opposite things about silence and must never be able to be
  /// confused for one another. "I can record" is a claim about the device that
  /// stays true across the whole call; this is a claim about right now that a
  /// device is only entitled to make once a frame has actually arrived.
  /// Published even while NOT recording, which the capability attribute never
  /// is. That is the whole difference between a sibling that has told us it is
  /// idle and one we have simply not heard from, and without it the two are the
  /// same reading — which is how a sibling that was recording all along came to
  /// be disqualified for a stretch it was holding.
  static const capturingAttribute = 'pangea_capturing';

  /// The attribute a device publishes to say whether it is the one carrying on
  /// with the call once the learner has two devices in it.
  ///
  /// A THIRD attribute, on the same plane and announcer as the two above, for
  /// the ownership design (call-device-ownership.instructions.md). Published
  /// UNCONDITIONALLY from the moment a device joins — carrying [_notChosen]
  /// until the learner picks it, and only then [_chosen] — because silence here
  /// has to mean "does not speak this protocol" (an older build), which is the
  /// whole basis of the participation test. That is why it is NOT seeded into
  /// [_announced] the way capability is: the `no` must actually be written.
  static const chosenAttribute = 'pangea_chosen';
  static const _chosen = 'yes';
  static const _notChosen = 'no';

  /// What a sibling's attributes say about whether it can record.
  ///
  /// Anything other than an explicit refusal reads as ABLE — no attribute, an
  /// older build that publishes none, a value from a future version this build
  /// does not understand. The exact counterpart of what [announceCanCapture]
  /// writes, and the reason the two are next to each other.
  static bool capableFromAttributes(Map<String, String> attributes) =>
      attributes[canCaptureAttribute] != _cannotRecord;

  /// What a sibling's attributes say about whether it is recording.
  ///
  /// The counterpart of what [announceCapturing] writes. Unlike
  /// [capableFromAttributes] directly above, this has no default to fall back
  /// on: a device that has published nothing is SILENT, which is neither a yes
  /// nor a no and settles nothing either way.
  static CaptureReport captureReportFromAttributes(
    String deviceId,
    Map<String, String> attributes,
  ) => CaptureReport.of(deviceId, attributes[capturingAttribute]);

  /// What a sibling's attributes say about whether it is the chosen device.
  ///
  /// Three-valued like [captureReportFromAttributes], and for the same reason:
  /// `yes` is a claim, `no` is participation without a claim, and anything else
  /// — absent, empty, or a value from a build this one does not speak — is
  /// SILENT, which settles nothing and is what marks an older build.
  static ChosenState chosenFromAttributes(Map<String, String> attributes) {
    switch (attributes[chosenAttribute]) {
      case _chosen:
        return ChosenState.chosen;
      case _notChosen:
        return ChosenState.notChosen;
      default:
        return ChosenState.silent;
    }
  }

  /// The picture the last recompute produced. Everything public below is a view
  /// of it, so the stored state and the state listeners were told about cannot
  /// come apart.
  _RosterPicture _picture = _RosterPicture.empty;

  /// Frozen while the connection is not up. A full reconnect empties the
  /// participant list and reports every participant as disconnected before
  /// refilling it, which is indistinguishable from everyone hanging up. Holding
  /// the last known picture means a network blip no longer reads as the other
  /// person leaving — which would have ended the call.
  bool _connected = false;

  CallRoster({
    required lk.Room room,
    required this.myUserId,
    this.metadataGrant = MetadataGrant.unknown,
  }) : _room = room {
    _room.addListener(recompute);
    recompute();
  }

  /// EVERYTHING this reads off the SFU, in one snapshot per recompute.
  ///
  /// One seam rather than several, so a test's fake room and the real one
  /// answer the same question at the same instant. Overridden in tests, which
  /// cannot stand up a live connection.
  @protected
  RosterRead get read {
    final me = _room.localParticipant;
    return RosterRead(
      remotes: [
        for (final entry in _room.remoteParticipants.entries)
          RosterMember(
            identity: entry.key,
            described: _described(entry.value.state),
            joinedAt: entry.value.joinedAt,
            audioPublications: entry.value.audioTrackPublications.length,
            mutedAudioPublications: entry.value.audioTrackPublications
                .where((p) => p.muted)
                .length,
            attributes: entry.value.attributes,
          ),
      ],
      me: me == null
          ? null
          : RosterMember(
              identity: me.identity,
              described: _described(me.state),
              joinedAt: me.joinedAt,
              attributes: me.attributes,
            ),
    );
  }

  /// Whether the SFU has described a participant, read through the state it
  /// reports.
  ///
  /// The SDK's own `hasInfo` says exactly this and is marked internal to its
  /// package, so reading it here is a warning rather than an answer. The
  /// participant state is the public projection of the same field: it starts
  /// `unknown` and is set, from the server's own value, in the one method that
  /// stores the participant info. The residual disagreement is a server state
  /// this SDK version does not know, which reads as undescribed and therefore
  /// as an unknown join time — the conservative direction, since an unknown
  /// join time never discards audio.
  static bool _described(lk.ParticipantState state) =>
      state != lk.ParticipantState.unknown;

  /// A join time worth believing, or null.
  ///
  /// Two ways it can be worthless and both have been seen. The SDK returns a
  /// fresh read of THIS device's clock when it has no server info, which would
  /// place a sibling's join wherever we happen to be looking from; and the
  /// protocol default for an unstamped `joinedAt` is zero, which reads as 1970
  /// — the same reading `ClockAnchor` already refuses on the wire, for the same
  /// reason. Sharing that rule is deliberate: a number this file would not
  /// believe about a clock is not a number the election should displace a
  /// recording over.
  static DateTime? usableJoinTime({
    required bool described,
    required DateTime joinedAt,
  }) {
    if (!described) return null;
    final ms = joinedAt.millisecondsSinceEpoch;
    if (ms <= 0 || ms >= ClockAnchor.clockCeilingMs) return null;
    return joinedAt;
  }

  @protected
  bool get roomConnected =>
      _room.connectionState == lk.ConnectionState.connected;

  /// Whether the connection is coming back, as opposed to gone.
  ///
  /// The SDK reports reconnecting while it is trying and disconnected once it
  /// has given up. Only the first is worth holding a picture for.
  @protected
  bool get roomRecovering =>
      _room.connectionState == lk.ConnectionState.connecting ||
      _room.connectionState == lk.ConnectionState.reconnecting;

  /// Publishes attributes for this device, and answers whether they went.
  ///
  /// FALSE when there is nobody to publish as. A silent no-op that returned
  /// normally is indistinguishable from a write that landed, and a caller that
  /// recorded it as landed would never come back to it.
  @protected
  Future<bool> publishAttributes(Map<String, String> attributes) async {
    final me = _room.localParticipant;
    if (me == null) return false;
    // Merged over what is already there. The SFU replaces the whole attribute
    // map, so writing only our key would delete anyone else's.
    await me.setAttributes({...me.attributes, ...attributes});
    return true;
  }

  /// Everyone else in the call, whichever account they belong to.
  Set<CallParticipant> get participants => _picture.participants;

  /// Whether someone other than this account is in the call.
  ///
  /// This is what makes a call a conversation rather than one person alone in a
  /// room, and what tells the caller their call was answered.
  bool get hasPeer => participants.any((p) => p.userId != myUserId);

  /// Whether the person on the other end cannot currently be heard.
  ///
  /// Over the PEER USER'S participants only: the remote list also carries this
  /// account's own sibling devices, and a muted second phone of MINE must
  /// never paint the peer as muted. True iff the peer has at least one audio
  /// publication and every one of them is muted -- one audible device means
  /// they can be heard, and no publications at all is "no signal yet", which
  /// is not a statement about their microphone.
  bool get peerMuted => _picture.peerMuted;

  bool _readPeerMuted(RosterRead snapshot) {
    var publications = 0;
    var muted = 0;
    for (final member in snapshot.remotes) {
      final who = CallParticipant.parse(member.identity, myUserId: myUserId);
      if (who.userId == myUserId) continue;
      publications += member.audioPublications;
      muted += member.mutedAudioPublications;
    }
    return publications > 0 && muted == publications;
  }

  /// This account's OTHER devices in the call.
  ///
  /// Drawn from the same list as everything else, so the recorder election and
  /// presence can never disagree about who is present.
  Iterable<String> get siblingDeviceIds => participants
      .where((p) => p.userId == myUserId)
      .map((p) => p.deviceId)
      .whereType<String>();

  /// When the SFU saw THIS device join, or null when it has not said.
  DateTime? get myJoinTime => _picture.myJoinedAt;

  /// When the SFU saw one of this account's other devices join.
  DateTime? siblingJoinTime(String deviceId) => _sibling(deviceId)?.joinedAt;

  /// The identity the SFU named THIS device by, or null before it has named
  /// one.
  ///
  /// The key `CallMedia`'s join-stamp store is held under, and the reason it is
  /// read from here rather than assembled from the account and the device id:
  /// the string is the SFU's, and only the SFU's copy of it is certain to
  /// match the one the store was keyed with.
  String? get myIdentity => _picture.myIdentity;

  /// The identity the SFU named one of this account's other devices by.
  String? siblingIdentity(String deviceId) => _sibling(deviceId)?.identity;

  /// Whether one of this account's other devices says it can record.
  ///
  /// A device this account cannot see reads as ABLE, for the same reason an
  /// unannounced one does: the only safe way to be wrong about a sibling is to
  /// defer to it.
  bool siblingCanCapture(String deviceId) =>
      _sibling(deviceId)?.canCapture ?? true;

  /// What one of this account's other devices has said about whether it is
  /// recording.
  ///
  /// A device this account cannot see is SILENT, which is the opposite default
  /// from [siblingCanCapture] and is not an inconsistency: a sibling we cannot
  /// see is one we have heard nothing from, and nothing is neither a statement
  /// that it holds a copy of what the learner just said nor a statement that it
  /// does not.
  CaptureReport siblingCaptureReport(String deviceId) =>
      _sibling(deviceId)?.capturing ?? CaptureReport.of(deviceId, null);

  /// What one of this account's other devices has published about being the
  /// chosen device.
  ///
  /// A device this account cannot see is SILENT, the same default as
  /// [siblingCaptureReport] and for the same reason: a sibling we have not seen
  /// is one we have heard nothing from, and the ownership arbiter must never
  /// treat that as either a claim or a denial.
  ChosenState siblingChosen(String deviceId) =>
      _sibling(deviceId)?.chosen ?? ChosenState.silent;

  CallParticipant? _sibling(String deviceId) {
    for (final p in participants) {
      if (p.userId == myUserId && p.deviceId == deviceId) return p;
    }
    return null;
  }

  /// Whether the SFU connection is currently up.
  bool get isConnected => _connected;

  /// Whether the connection is down but coming back. The participant picture is
  /// frozen while this is true, so callers reading presence also need to know
  /// the freeze is on — a blip must show as "reconnecting", not as silence.
  bool get isRecovering => !_connected && roomRecovering;

  /// Re-reads the participant list. Called on every notification from the room,
  /// and directly by tests.
  @visibleForTesting
  void recompute() {
    final connected = roomConnected;
    final wasConnected = _connected;
    _connected = connected;

    // While the connection is coming back the participant list is not evidence
    // of anything — it is emptied on a full restart and refilled afterwards, so
    // the last picture taken while connected is the best available answer.
    //
    // Once it has gone for good that stops being true. Holding the picture then
    // means the call is never seen to end, and the microphone stays open in a
    // conversation that finished when the connection did.
    if (!connected) {
      if (roomRecovering) {
        if (wasConnected) notifyListeners();
        return;
      }
      if (wasConnected || _picture.participants.isNotEmpty) {
        _picture = _RosterPicture.empty;
        notifyListeners();
      }
      return;
    }

    // ONE read, and everything below is derived from it. Level-triggered like
    // the list itself: re-read whole on every notification, so a missed mute
    // event costs one repaint, not the truth.
    final snapshot = read;
    final next = _RosterPicture(
      participants: {for (final member in snapshot.remotes) _describe(member)},
      myJoinedAt: snapshot.me == null
          ? null
          : usableJoinTime(
              described: snapshot.me!.described,
              joinedAt: snapshot.me!.joinedAt,
            ),
      // NOT filtered by [usableJoinTime] beside it, because it is not a
      // reading of anything: an identity is what the SFU CALLS this device,
      // and it is exactly as true on a membership the SFU has not yet
      // described as on one it has.
      myIdentity: snapshot.me?.identity,
      peerMuted: _readPeerMuted(snapshot),
    );

    // ONE inequality, over everything anyone downstream reads. The predicate
    // this replaced compared the participant SET and one mute flag, and a set
    // compares participants by identity alone — so a sibling's join time or its
    // capability could change and land in complete silence, which is exactly
    // the shape of change the election now depends on.
    //
    // Notified on reconnection even when nothing else changed, because the
    // frozen window ended and listeners gated on connectedness need to know.
    final changed = !wasConnected || next != _picture;
    // Stored whether or not anyone is told, so a skipped notification cannot
    // leave the comparison arguing against a picture nobody holds any more.
    _picture = next;
    // Level-triggered like the rest of this: an announcement that could not be
    // written earlier is tried again here, so the window in which this device's
    // siblings hold a stale answer closes when the signal recovers rather than
    // lasting the call.
    _reassertAnnouncement();
    if (!changed) return;
    notifyListeners();
  }

  /// One participant, as this roster believes them.
  ///
  /// A method rather than an expression inside [recompute] because three
  /// separate rules apply to the same raw member — which join stamps are worth
  /// believing, what silence says about capability, and what silence says about
  /// recording — and each of them has the opposite default from at least one of
  /// the others.
  CallParticipant _describe(RosterMember member) {
    final who = CallParticipant.parse(member.identity, myUserId: myUserId);
    final deviceId = who.deviceId;
    return who.describedBy(
      joinedAt: usableJoinTime(
        described: member.described,
        joinedAt: member.joinedAt,
      ),
      canCapture: capableFromAttributes(member.attributes),
      // An identity with no device segment says nothing. There is no device to
      // attribute the statement to, and a report that named nobody could be
      // matched against any successor at all.
      capturing: deviceId == null
          ? null
          : captureReportFromAttributes(deviceId, member.attributes),
      // Unlike the two above, the ownership claim is read straight off the
      // attributes: it is a fact about what this participant published, and the
      // arbiter only ever asks it of a device it already knows to be a sibling.
      chosen: chosenFromAttributes(member.attributes),
    );
  }

  /// What this device's siblings have ACTUALLY been told, keyed by attribute.
  ///
  /// Seeded with what silence already says about CAPABILITY, so announcing a
  /// value a sibling would have assumed anyway costs no round trip. There is
  /// deliberately no such seed for the recording state: silence says nothing
  /// there, so "I am not recording" is a sentence that has to actually be said,
  /// and the first election of a call says it.
  /// Moved only once a write has landed, which is what makes it safe to rank
  /// on — the election reads the landed value rather than the live one, because
  /// a device that stood aside the instant it found out, while every sibling
  /// still read it as able, would tie them all on capability and lose the
  /// device-id tiebreak to itself, and nobody would record for as long as the
  /// signal stayed stuck.
  final Map<String, String> _announced = {canCaptureAttribute: _canRecord};

  /// What it wants them to be told. Differs from [_announced] precisely while
  /// an announcement is outstanding.
  final Map<String, String> _wanted = {};

  /// Whether a write is on the wire right now.
  bool _announcing = false;

  /// Callers waiting to hear that what they asked for has actually reached the
  /// SFU.
  ///
  /// Announcing is normally fire-and-forget, because nothing waits on a signal
  /// round trip. One caller does: a device about to stop recording must not
  /// stop while its siblings can still read it as recording, and that is an
  /// ORDER between two things this device controls rather than a race it can
  /// hope to win.
  ///
  /// Each waiter carries the VALUE it is waiting to see, not just the attribute
  /// it is about. Keyed by attribute alone, a caller waiting for "not
  /// recording" was released by a later "recording" landing — the exact
  /// opposite of what it asked for, and it resumed a stop on the strength of
  /// it.
  final List<_Announcement> _settling = [];

  /// The write currently on the wire, or null when there is none.
  ///
  /// THE THIRD FACT, and its absence is what let a waiter be answered by
  /// bookkeeping rather than by what a sibling can actually read. [_wanted] is
  /// what this device intends to say; [_announced] is what it last FINISHED
  /// saying. Neither knows about a write that has left and not yet landed — so
  /// a value that has landed is not visible when a contradicting one is already
  /// on its way to replace it, and a caller told "that is already true" would
  /// stop its recorder just as the older write arrived to say otherwise.
  Map<String, String>? _inFlight;

  /// Whether a sibling reading right now would see [value] for [key], and would
  /// go on seeing it once everything already sent has arrived.
  bool _visible(String key, String value) {
    if (_announced[key] != value) return false;
    final flying = _inFlight;
    return flying == null || !flying.containsKey(key) || flying[key] == value;
  }

  /// What this device's siblings have actually been told about its capability.
  bool get announcedCanCapture =>
      _announced[canCaptureAttribute] != _cannotRecord;

  /// Tells this account's other devices whether this one can record.
  Future<void> announceCanCapture(bool canCapture) =>
      _announce(canCaptureAttribute, canCapture ? _canRecord : _cannotRecord);

  /// Tells this account's other devices whether this one is the chosen device.
  ///
  /// The caller publishes `false` UNCONDITIONALLY the moment it joins — that
  /// standing `no` is what makes a silent sibling read as "does not speak this
  /// protocol" rather than "has not answered yet" — and `true` only once the
  /// learner has picked this device. On the same announcer as the two above, so
  /// there is no new channel and no new failure mode.
  Future<void> announceChosen(bool chosen) =>
      _announce(chosenAttribute, chosen ? _chosen : _notChosen);

  /// Tells them which uninterrupted stretch of audio is reaching this device's
  /// recorder, or that none is.
  ///
  /// ASSERTED LATE AND RETRACTED EARLY, and the asymmetry is the whole
  /// discipline. A run is named only on the strength of a frame that actually
  /// arrived, because this is the one signal a displaced sibling is allowed to
  /// destroy its own captured audio on — a device that published it because it
  /// INTENDED to record would be telling a sibling to throw away the only copy
  /// of what the learner said. The retraction goes the other way and is
  /// published on the INTENTION to stop, so it is already on the wire before
  /// the audio stops rather than chasing it.
  ///
  /// The returned future completes when the value is VISIBLE — landed, with
  /// nothing contradicting still on the wire — which is what a caller ordering
  /// its own stop behind this actually needs.
  ///
  /// THE RESIDUE, and it is the last of it. When a write cannot be made to go
  /// at all the waiter is released anyway, so a device whose signal channel has
  /// stopped answering stops its recorder with a stale run still showing. The
  /// alternative is a microphone held open for as long as the channel stays
  /// broken, which is worse. Note this only bites where an EARLIER write
  /// succeeded — a device that never managed to publish a run has no claim for
  /// a sibling to act on — so it needs a channel that worked and then stopped.
  /// Beyond it lies the one that cannot be closed from here at all: a sibling
  /// reads a snapshot the SFU pushed at some earlier, unknowable instant, and
  /// LiveKit offers no sequence or timestamp against which one could be called
  /// current.
  Future<void> announceCapturing(String? run) =>
      _announce(capturingAttribute, CaptureReport.published(run));

  /// Publishes one fact, and everything else outstanding along with it.
  ///
  /// SINGLE-FLIGHT AND COALESCING. One write is on the wire at a time, and the
  /// loop re-reads the wanted values after each one, so a caller whose intent
  /// arrived mid-write is never dropped in favour of the value already flying —
  /// the same rule the memoised stop in the recorder states.
  ///
  /// ONE loop for every attribute, not one per fact. `setAttributes` replaces
  /// the whole map and [publishAttributes] merges over the copy it can see, so
  /// two announcements in flight at once would each merge over a picture taken
  /// before the other landed and one of them would be silently lost. Everything
  /// outstanding goes in the same write for the same reason it costs nothing
  /// to: it is one round trip either way.
  ///
  /// AND THE FIRST WRITE WAITS FOR THE CALLER TO FINISH SPEAKING. An election
  /// settles several facts in one synchronous pass and announces each as it
  /// decides it; composing the write on the first of them puts every later one
  /// behind a whole round trip. That is not a tidiness problem. The recording
  /// retraction is the last fact an election settles and the one that has to
  /// travel before the audio stops, and queueing it behind a capability write
  /// is precisely how it ended up arriving after. Yielding once here costs
  /// nothing — the write was always going to be asynchronous — and makes the
  /// batching a property of the announcer rather than something every caller
  /// has to arrange.
  Future<void> _announce(String key, String value) {
    _wanted[key] = value;
    // Already true as far as the siblings are concerned, AND nothing on the
    // wire is about to make it untrue. Both halves, because the second is the
    // one that was missing.
    if (_visible(key, value)) return Future<void>.value();
    final waiting = _Announcement(key, value);
    _settling.add(waiting);
    if (!_announcing) {
      _announcing = true;
      unawaited(_runAnnouncements());
    }
    return waiting.settled.future;
  }

  Future<void> _runAnnouncements() async {
    try {
      // The yield. Anything else this turn wants said is in [_wanted] by the
      // time the loop below composes its first write.
      await Future<void>.value();
      while (true) {
        final pending = <String, String>{
          for (final entry in _wanted.entries)
            if (_announced[entry.key] != entry.value) entry.key: entry.value,
        };
        if (pending.isEmpty) return;
        // Published WHILE IT FLIES, so a caller arriving mid-write can see that
        // its value is about to be replaced rather than reading the last
        // completed write and concluding it is already true.
        _inFlight = pending;
        final bool landed;
        try {
          // A failed write RETURNS rather than spinning. The intent stays
          // outstanding and the next recompute re-asserts it; retrying inside
          // this loop would hammer a signal channel that has already answered.
          landed = await _write(pending);
        } finally {
          _inFlight = null;
        }
        // A write that did not go leaves everything as it was. The intent
        // stays outstanding for the next recompute to re-assert, and the
        // callers still waiting are released by the exit below rather than
        // held on a channel that has stopped answering.
        if (!landed) return;
        // Recorded only once the write actually happened. Recording it first
        // would have a device that never reached the SFU believe its siblings
        // knew, and stand aside on their behalf.
        _announced.addAll(pending);
        // Released AS SOON AS what they asked for is visible, rather than when
        // the whole queue drains. A caller here is holding a recorder's stop
        // open; making it wait out writes about something else would keep a
        // microphone running for round trips that have nothing to do with it.
        _settleVisible();
      }
    } finally {
      // Cleared HERE rather than from a completion callback, so there is no
      // instant in which the loop has exited and a caller still reads the run
      // as live — which would drop that caller's intent for good.
      _announcing = false;
      // AND NOBODY WAITS FOREVER. Whatever is still outstanding when the loop
      // gives up is released, because what a caller is waiting for is the
      // question to be SETTLED and "it is not going to be said" is an answer. A
      // recorder holding its microphone open on a signal channel that has
      // stopped answering would be a worse bug than the one the wait exists to
      // fix. See [announceCapturing] for what that costs.
      for (final waiting in _settling) {
        if (!waiting.settled.isCompleted) waiting.settled.complete();
      }
      _settling.clear();
    }
  }

  void _settleVisible() {
    _settling.removeWhere((waiting) {
      if (!_visible(waiting.key, waiting.value)) return false;
      if (!waiting.settled.isCompleted) waiting.settled.complete();
      return true;
    });
  }

  Future<bool> _write(Map<String, String> attributes) async {
    try {
      return await publishAttributes(attributes);
    } catch (e, s) {
      // Loudly, and naming the likeliest cause: `setAttributes` waits five
      // seconds for the SFU to answer and then throws, and it completes with an
      // error when the server refuses — which is what a call token minted
      // without the grant to update its own metadata looks like from here.
      // Both halves of the election are inert while this fails, and it fails
      // quietly enough to look like it works. The failure is SAFE in the
      // direction that matters: siblings that never hear this device attest to
      // recording will deliver their own tails rather than drop them.
      Logs().w(
        'Could not tell this account other devices what this one can do or is '
        'doing (${attributes.keys.join(', ')}); the call token most likely '
        'lacks CanUpdateOwnMetadata',
        e,
        s,
      );
      // AND SOMEWHERE IT CAN BE COUNTED. The sentence above was written
      // correctly, and named the right cause, while the failure it describes ran
      // in production for the life of the feature: [Logs] reaches the in-app log
      // viewer and nothing else, so nobody who was not already looking at a
      // device ever saw one.
      //
      // ONCE PER SESSION, because this is level-triggered rather than bounded.
      // Every recompute re-asserts an outstanding intent, so a channel that has
      // stopped answering fails again on every room notification for the whole
      // call — a report per failure would be one issue per participant event.
      // The first one carries the signal and Sentry's affected-user count
      // carries the size.
      //
      // Severity is left to [ErrorHandler]'s table, which reads this as an
      // error. That is the reading this failure was owed: it is never the
      // learner's doing, and its safe direction — siblings that hear nothing
      // deliver their own tails rather than drop them — is what let it look
      // like it was working.
      ErrorHandler.logErrorOnce(
        key: attributesUnpublishedKey,
        e: e,
        s: s,
        data: {
          // What the throw itself does not say. See [attributesUnpublishedCost].
          'lost': attributesUnpublishedCost,
          // Attribute NAMES, never the values: a published run names a stretch
          // of a learner's conversation.
          'attributes': attributes.keys.toList()..sort(),
          // The half that tells a refusal from an outage. See [metadataGrant].
          'tokenGrant': metadataGrant.name,
        },
      );
      return false;
    }
  }

  /// The session-throttle key the unpublished-attributes report is filed under.
  ///
  /// Named so the report and the test that pins its budget spend one string.
  static const attributesUnpublishedKey = 'call_roster.attributes_unpublished';

  /// What a write that never reached the siblings COSTS, carried on the report.
  ///
  /// In `data` rather than in the exception, because it belongs to neither of
  /// the two places a report can otherwise put a sentence. The thrown `e` is
  /// whatever the signal channel raised — a five-second timeout, a refusal —
  /// and no shape of it says what is lost when it fails. Wrapping `e` to say so
  /// would change the runtime type that the severity table and the fingerprint
  /// both read, which is exactly why #8660 deleted these sentences rather than
  /// folding them in; and handing the reporter a description it does not report
  /// is the same #8660 defect, a string that reaches `debugPrint` and nowhere
  /// else. `data` is on the Sentry event, so it is searchable there.
  ///
  /// Named, like [attributesUnpublishedKey], so the report and the test that
  /// pins it spend one string.
  static const attributesUnpublishedCost =
      "This device could not tell the account's other devices what it can "
      'do or is doing; the recorder election is running without its '
      'capability layer';

  void _reassertAnnouncement() {
    for (final entry in _wanted.entries) {
      if (_announced[entry.key] == entry.value) continue;
      // One call is enough: the loop it starts picks up every other
      // outstanding value in the same write.
      unawaited(_announce(entry.key, entry.value));
      return;
    }
  }

  /// Whether this account has another device in the call at all.
  ///
  /// Read by the recorder before it holds a stop open waiting for a retraction:
  /// a device alone has nobody to mislead, and nobody to wait for.
  bool get hasSiblings => siblingDeviceIds.isNotEmpty;

  @override
  void dispose() {
    _room.removeListener(recompute);
    super.dispose();
  }
}

/// One caller waiting for one value to become visible to the siblings.
class _Announcement {
  final String key;
  final String value;
  final Completer<void> settled = Completer<void>();

  _Announcement(this.key, this.value);
}

/// Everything a listener can observe about the roster, in one comparable value.
///
/// The point is that the notify predicate is DERIVED from what is stored rather
/// than hand-maintained beside it. Participants compare through
/// [CallParticipant.state] rather than through their own `==`, which
/// deliberately ignores the two fields the election reads.
@immutable
class _RosterPicture {
  final Set<CallParticipant> participants;
  final DateTime? myJoinedAt;

  /// Null exactly when the SFU has given this device no membership at all,
  /// which is a different absence from [myJoinedAt]'s: an identity is not a
  /// time, so it survives a membership the SFU has named but not yet
  /// described.
  final String? myIdentity;
  final bool peerMuted;

  const _RosterPicture({
    required this.participants,
    required this.myJoinedAt,
    required this.myIdentity,
    required this.peerMuted,
  });

  static const empty = _RosterPicture(
    participants: {},
    myJoinedAt: null,
    myIdentity: null,
    peerMuted: false,
  );

  Set<(String, String, String?, DateTime?, bool, CaptureReport?, ChosenState)>
  get _states => participants.map((p) => p.state).toSet();

  @override
  bool operator ==(Object other) =>
      other is _RosterPicture &&
      other.myJoinedAt == myJoinedAt &&
      other.myIdentity == myIdentity &&
      other.peerMuted == peerMuted &&
      setEquals(other._states, _states);

  @override
  int get hashCode => Object.hash(
    myJoinedAt,
    myIdentity,
    peerMuted,
    Object.hashAllUnordered(_states),
  );
}
