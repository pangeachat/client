import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' show Logs;

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

  /// That device's own word that audio is reaching its recorder RIGHT NOW, or
  /// null when it has not said so.
  ///
  /// Silence is null, and null is the DEFAULT — the opposite polarity from
  /// [canCapture] beside it, because the two answer different questions.
  /// [canCapture] ranks a fleet and has to defer to a sibling it has not heard
  /// from; this one is the only thing that ever authorises throwing captured
  /// audio away, and deferring there destroys the copy.
  ///
  /// Out of [==] for the same reason [joinedAt] is: presence dedups by set
  /// equality and this moves while the same people are in the same call.
  /// [state] is what carries it to the notify predicate.
  final CaptureAttestation? capturing;

  const CallParticipant({
    required this.userId,
    this.deviceId,
    this.joinedAt,
    this.canCapture = true,
    this.capturing,
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
      if (identity == myUserId) return CallParticipant(userId: myUserId);
      if (identity.startsWith('$myUserId:')) {
        final rest = identity.substring(myUserId.length + 1);
        // Only when what follows is a single segment. Another user whose id
        // extends ours — ours with a port, say — would otherwise be read as one
        // of our own devices, and a real peer would not count as present.
        if (!rest.contains(':')) {
          return CallParticipant(userId: myUserId, deviceId: rest);
        }
      }
    }
    // Someone else. The last segment is taken as their device, which is what
    // the token service always appends.
    final split = identity.lastIndexOf(':');
    if (split <= 0 ||
        !identity.startsWith('@') ||
        identity.indexOf(':') == split) {
      return CallParticipant(userId: identity);
    }
    return CallParticipant(
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
    CaptureAttestation? capturing,
  }) => CallParticipant(
    userId: userId,
    deviceId: deviceId,
    joinedAt: joinedAt,
    canCapture: canCapture,
    capturing: capturing,
  );

  /// Everything about this participant that anyone downstream reads, INCLUDING
  /// the three fields [==] leaves out.
  ///
  /// A record, so comparing two of them compares every field structurally. This
  /// is what the roster's notify predicate is built from: a hand-maintained
  /// list of "fields worth notifying about" is how a capability change came to
  /// land in silence.
  (String, String?, DateTime?, bool, CaptureAttestation?) get state =>
      (userId, deviceId, joinedAt, canCapture, capturing);

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

  final lk.Room _room;

  /// The attribute a device publishes to tell its siblings whether it can
  /// record, and the two values it takes.
  ///
  /// A value rather than the key's presence, because attributes are merged
  /// rather than replaced and there is no clean way to take a key back.
  static const canCaptureAttribute = 'pangea_can_capture';
  static const _canRecord = 'yes';
  static const _cannotRecord = 'no';

  /// The attribute a device publishes while audio is ACTUALLY reaching its
  /// recorder, and the value it takes when it is not.
  ///
  /// A SECOND attribute rather than a richer value in the first one, because
  /// the two mean opposite things about silence and must never be able to be
  /// confused for one another. "I can record" is a claim about the device that
  /// stays true across the whole call; this is a claim about right now that a
  /// device is only entitled to make once a frame has actually arrived.
  static const capturingAttribute = 'pangea_capturing';
  static const _notCapturing = 'no';

  /// What a sibling's attributes say about whether it can record.
  ///
  /// Anything other than an explicit refusal reads as ABLE — no attribute, an
  /// older build that publishes none, a value from a future version this build
  /// does not understand. The exact counterpart of what [announceCanCapture]
  /// writes, and the reason the two are next to each other.
  static bool capableFromAttributes(Map<String, String> attributes) =>
      attributes[canCaptureAttribute] != _cannotRecord;

  /// A sibling's own word that it is recording, or null when it has not given
  /// one.
  ///
  /// The counterpart of what [announceCapturing] writes, and the mirror image
  /// of [capableFromAttributes] directly above: there, anything but a refusal
  /// is a yes; here, anything but the affirmative value is a no. Both defaults
  /// are the safe one for the question being asked. Deferring to an unheard
  /// sibling costs a stretch of the recording; believing an unheard sibling
  /// holds a copy costs the copy.
  static CaptureAttestation? attestationFromAttributes(
    String deviceId,
    Map<String, String> attributes,
  ) => CaptureAttestation.of(deviceId, attributes[capturingAttribute]);

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

  CallRoster({required lk.Room room, required this.myUserId}) : _room = room {
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

  /// Whether one of this account's other devices says it can record.
  ///
  /// A device this account cannot see reads as ABLE, for the same reason an
  /// unannounced one does: the only safe way to be wrong about a sibling is to
  /// defer to it.
  bool siblingCanCapture(String deviceId) =>
      _sibling(deviceId)?.canCapture ?? true;

  /// One of this account's other devices attesting that it is recording, or
  /// null.
  ///
  /// A device this account cannot see attests to NOTHING, which is the opposite
  /// default from [siblingCanCapture] and is not an inconsistency: a sibling we
  /// cannot see is one we have heard nothing from, and nothing is not a
  /// statement that it holds a copy of what the learner just said.
  CaptureAttestation? siblingCaptureAttestation(String deviceId) =>
      _sibling(deviceId)?.capturing;

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
      // An identity with no device segment attests to nothing. There is no
      // device to attribute the statement to, and an attestation that named
      // nobody could be matched against any successor at all.
      capturing: deviceId == null
          ? null
          : attestationFromAttributes(deviceId, member.attributes),
    );
  }

  /// What this device's siblings have ACTUALLY been told, keyed by attribute.
  ///
  /// Seeded with what silence already says, so announcing a value a sibling
  /// would have assumed anyway costs no round trip: able, and not recording.
  /// Moved only once a write has landed, which is what makes it safe to rank
  /// on — the election reads the landed value rather than the live one, because
  /// a device that stood aside the instant it found out, while every sibling
  /// still read it as able, would tie them all on capability and lose the
  /// device-id tiebreak to itself, and nobody would record for as long as the
  /// signal stayed stuck.
  final Map<String, String> _announced = {
    canCaptureAttribute: _canRecord,
    capturingAttribute: _notCapturing,
  };

  /// What it wants them to be told. Differs from [_announced] precisely while
  /// an announcement is outstanding.
  final Map<String, String> _wanted = {};

  /// Whether a write is on the wire right now.
  bool _announcing = false;

  /// What this device's siblings have actually been told about its capability.
  bool get announcedCanCapture =>
      _announced[canCaptureAttribute] != _cannotRecord;

  /// Tells this account's other devices whether this one can record.
  Future<void> announceCanCapture(bool canCapture) =>
      _announce(canCaptureAttribute, canCapture ? _canRecord : _cannotRecord);

  /// Tells them whether audio is reaching this device's recorder right now.
  ///
  /// Only ever said on the strength of a frame that actually arrived. This is
  /// the one signal a displaced sibling is allowed to destroy its own captured
  /// audio on, so a device that published it because it INTENDED to record
  /// would be telling a sibling to throw away the only copy of what the learner
  /// said.
  Future<void> announceCapturing(bool capturing) => _announce(
    capturingAttribute,
    capturing ? CaptureAttestation.attested : _notCapturing,
  );

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
  Future<void> _announce(String key, String value) async {
    _wanted[key] = value;
    if (_announcing) return;
    _announcing = true;
    try {
      while (true) {
        final pending = <String, String>{
          for (final entry in _wanted.entries)
            if (_announced[entry.key] != entry.value) entry.key: entry.value,
        };
        if (pending.isEmpty) return;
        // A failed write RETURNS rather than spinning. The intent stays
        // outstanding and the next recompute re-asserts it; retrying inside
        // this loop would hammer a signal channel that has already answered.
        if (!await _write(pending)) return;
        // Recorded only once the write actually happened. Recording it first
        // would have a device that never reached the SFU believe its siblings
        // knew, and stand aside on their behalf.
        _announced.addAll(pending);
      }
    } finally {
      // Cleared HERE rather than from a completion callback, so there is no
      // instant in which the loop has exited and a caller still reads the run
      // as live — which would drop that caller's intent for good.
      _announcing = false;
    }
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
      return false;
    }
  }

  void _reassertAnnouncement() {
    for (final entry in _wanted.entries) {
      if (_announced[entry.key] == entry.value) continue;
      // One call is enough: the loop it starts picks up every other
      // outstanding value in the same write.
      unawaited(_announce(entry.key, entry.value));
      return;
    }
  }

  @override
  void dispose() {
    _room.removeListener(recompute);
    super.dispose();
  }
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
  final bool peerMuted;

  const _RosterPicture({
    required this.participants,
    required this.myJoinedAt,
    required this.peerMuted,
  });

  static const empty = _RosterPicture(
    participants: {},
    myJoinedAt: null,
    peerMuted: false,
  );

  Set<(String, String?, DateTime?, bool, CaptureAttestation?)> get _states =>
      participants.map((p) => p.state).toSet();

  @override
  bool operator ==(Object other) =>
      other is _RosterPicture &&
      other.myJoinedAt == myJoinedAt &&
      other.peerMuted == peerMuted &&
      setEquals(other._states, _states);

  @override
  int get hashCode =>
      Object.hash(myJoinedAt, peerMuted, Object.hashAllUnordered(_states));
}
