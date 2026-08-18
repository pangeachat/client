import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/pangea_voip_delegate.dart';
import 'package:fluffychat/routes/chat/calls/rtc_focus.dart';

/// Owns one account's MatrixRTC calling.
///
/// One per Client, mirroring how the other per-account services are held, because
/// the SDK's [VoIP] instance is per-client and its membership identifier is
/// per-instance — constructing a second one for the same account drops any call the
/// first was tracking.
class CallService {
  final Client client;
  final PangeaVoipDelegate delegate;
  final CallTokenRepo _tokens;

  VoIP? _voip;
  RtcFocus? _focus;

  CallService(
    this.client, {
    PangeaVoipDelegate? delegate,
    CallTokenRepo? tokenRepo,
  }) : delegate = delegate ?? PangeaVoipDelegate(),
       _tokens = tokenRepo ?? CallTokenRepo();

  /// The focus this homeserver advertises, or null if it advertises none.
  ///
  /// Read once per service: `.well-known` is fetched at login and does not change
  /// under a running session.
  RtcFocus? get focus => _focus ??= RtcFocus.fromWellKnown(client.wellKnown);

  /// Whether calling is available for this account at all.
  ///
  /// False on a homeserver with no RTC focus configured. Callers use this to hide
  /// the call affordance rather than offering a button that cannot work.
  bool get isAvailable => focus != null;

  /// Constructed lazily and exactly once.
  ///
  /// Deliberately not built in the constructor: `VoIP()` is not inert. It scans every
  /// joined room for existing call memberships and can invoke
  /// `delegate.handleNewGroupCall` before returning, and it dereferences
  /// `delegate.mediaDevices` inline — so it must not run until the delegate is fully
  /// live, and should not run at all for an account that never places a call.
  VoIP get voip => _voip ??= VoIP(client, delegate);

  /// Whether a call is already running in [room], per room state rather than local
  /// belief — so a second device, or this device after a restart, sees the same answer.
  bool hasActiveCall(Room room) => room.hasActiveGroupCall(voip);

  /// Joins (or starts) the call in [room], returning the session and the grant needed
  /// to connect its media.
  ///
  /// The two halves are deliberately returned together: the SDK's session carries the
  /// Matrix side only, and the LiveKit grant is obtained separately by the app. A
  /// caller holding one without the other has a call that either nobody can see or
  /// nobody can hear.
  Future<CallJoin> join(Room room) async {
    final f = focus;
    if (f == null) {
      throw StateError('this homeserver advertises no MatrixRTC focus');
    }

    // Room-scoped call id: one direct message room holds at most one live call, and
    // both clients derive the same id without coordinating.
    final session = await voip.fetchOrCreateGroupCall(
      room.id,
      room,
      f.backendForRoom(room.id),
      'm.call',
      'm.room',
      // Defaults to true, which pre-generates and broadcasts an E2EE key before the
      // call even starts. With e2eeEnabled false the SDK returns early from that work
      // anyway, so this changes no behaviour — it just stops us asking for key
      // distribution we have deliberately turned off.
      preShareKey: false,
    );

    final grant = await _tokens.requestToken(
      client: client,
      roomId: room.id,
      focusServiceUrl: f.serviceUrl,
    );

    return CallJoin(session: session, grant: grant);
  }

  /// Publishes our membership, making the call visible to the other participant.
  Future<void> enter(GroupCallSession session) => session.enter();

  /// Retracts our membership and tears the session down.
  Future<void> leave(GroupCallSession session) => session.leave();

  void dispose() {
    _voip = null;
    _focus = null;
  }

  @visibleForTesting
  bool get voipConstructed => _voip != null;
}

/// A joined call: the Matrix session, and permission to connect its media.
class CallJoin {
  final GroupCallSession session;
  final CallToken grant;
  const CallJoin({required this.session, required this.grant});
}
