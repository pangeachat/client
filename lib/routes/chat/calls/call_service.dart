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

  /// The session this device has joined, if any. One at a time: the SDK's
  /// membership is per-VoIP-instance, so a second concurrent call on the same
  /// account would overwrite the first's identity.
  GroupCallSession? _current;

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

  /// Joins (or starts) the call in [room], returning the grant needed to connect
  /// its media.
  ///
  /// The Matrix session is kept here rather than handed back. A caller does
  /// nothing with it but pass it to [announce] and [retract], and the SDK object
  /// cannot be stood up outside a live VoIP instance — so holding it here is both
  /// simpler for callers and what lets the calling flow be tested at all.
  Future<CallToken> join(Room room) async {
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

    _current = session;
    return grant;
  }

  /// Publishes our membership, making the call visible to the other participant.
  /// Announces this device as a participant, so the peer sees us in the call.
  ///
  /// Separate from [join] because the two are not simultaneous by design: media
  /// comes up in between, so a peer never sees a participant who cannot yet be
  /// heard.
  Future<void> announce() async => _current?.enter();

  /// Retracts our membership and tears the session down.
  ///
  /// Idempotent: the session is cleared first, so a hangup racing a disconnect
  /// leaves exactly once.
  Future<void> retract() async {
    final session = _current;
    _current = null;
    await session?.leave();
  }

  void dispose() {
    _current = null;
    _voip = null;
    _focus = null;
  }

  @visibleForTesting
  bool get hasJoinedSession => _current != null;

  @visibleForTesting
  bool get voipConstructed => _voip != null;
}
