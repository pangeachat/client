import 'package:matrix/matrix.dart';

/// Whether a call the SDK has noticed should ring on this device.
///
/// The SDK reports every call it discovers, including the one this device just
/// started, and including calls whose participants have all gone. Ringing on
/// those would mean a learner's own outgoing call rings back at them, and calls
/// that ended keep ringing until their state expires.
class IncomingCall {
  /// Everyone currently in the call, as the room sees them.
  final Iterable<CallMembership> memberships;

  /// This account.
  final String myUserId;

  const IncomingCall({required this.memberships, required this.myUserId});

  Iterable<CallMembership> get _live => memberships.where((m) => !m.isExpired);

  /// True when someone else is in the call and this account is not.
  ///
  /// Not in it means no device of this account — answering on a phone must stop
  /// a laptop ringing, and the laptop learns that from the phone's membership
  /// appearing, not from a message.
  bool get shouldRing {
    var someoneElse = false;
    for (final m in _live) {
      if (m.userId == myUserId) return false;
      someoneElse = true;
    }
    return someoneElse;
  }

  /// Who is calling, for the prompt. Null when nobody is.
  String? get callerId => _caller?.userId;

  /// Identifies THIS call, as distinct from the next one in the same room.
  ///
  /// A call id is derived from the room, so it cannot tell two calls apart. The
  /// caller's membership is per-join, so it can — which is what lets a decline
  /// stick to the call it declined without silencing the conversation forever.
  String? get callerSession => _caller?.membershipId;

  CallMembership? get _caller {
    for (final m in _live) {
      if (m.userId != myUserId) return m;
    }
    return null;
  }
}
