import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart' as lk;

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

  const CallParticipant({required this.userId, this.deviceId});

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

  Set<CallParticipant> _participants = const {};

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

  /// The SFU's current participant list. Overridden in tests, which cannot
  /// stand up a real connection.
  @protected
  Iterable<String> get remoteIdentities => _room.remoteParticipants.keys;

  @protected
  bool get roomConnected =>
      _room.connectionState == lk.ConnectionState.connected;

  /// Everyone else in the call, whichever account they belong to.
  Set<CallParticipant> get participants => _participants;

  /// Whether someone other than this account is in the call.
  ///
  /// This is what makes a call a conversation rather than one person alone in a
  /// room, and what tells the caller their call was answered.
  bool get hasPeer => _participants.any((p) => p.userId != myUserId);

  /// This account's OTHER devices in the call.
  ///
  /// Drawn from the same list as everything else, so the recorder election and
  /// presence can never disagree about who is present.
  Iterable<String> get siblingDeviceIds => _participants
      .where((p) => p.userId == myUserId)
      .map((p) => p.deviceId)
      .whereType<String>();

  /// Whether the SFU connection is currently up.
  bool get isConnected => _connected;

  /// Re-reads the participant list. Called on every notification from the room,
  /// and directly by tests.
  @visibleForTesting
  void recompute() {
    final connected = roomConnected;
    final wasConnected = _connected;
    _connected = connected;

    // While the connection is down the participant list is not evidence of
    // anything — it is emptied on a full restart and refilled afterwards. The
    // last picture taken while connected is the best available answer.
    if (!connected) {
      if (wasConnected) notifyListeners();
      return;
    }

    final next = remoteIdentities
        .map((id) => CallParticipant.parse(id, myUserId: myUserId))
        .toSet();
    // Notified on reconnection even when the list is unchanged, because the
    // frozen window ended and listeners gated on connectedness need to know.
    if (wasConnected && setEquals(next, _participants)) return;
    _participants = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _room.removeListener(recompute);
    super.dispose();
  }
}
