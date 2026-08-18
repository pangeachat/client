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
  final RtcFocusDiscovery _discovery;

  VoIP? _voip;
  RtcFocus? _focus;
  Future<RtcFocus?>? _resolving;

  /// The session this device has joined, if any. One at a time: the SDK's
  /// membership is per-VoIP-instance, so a second concurrent call on the same
  /// account would overwrite the first's identity.
  GroupCallSession? _current;

  /// Claimed synchronously by [join] before its first await.
  ///
  /// Checking [_current] alone is check-then-act across three round-trips: two
  /// joins would both pass the check, both create sessions, and the second
  /// assignment would orphan the first — leaving a membership advertised that
  /// nothing holds a handle to.
  bool _joining = false;

  /// The in-flight retract, so concurrent callers await one attempt.
  Future<void>? _retracting;

  CallService(
    this.client, {
    PangeaVoipDelegate? delegate,
    CallTokenRepo? tokenRepo,
    RtcFocusDiscovery? focusDiscovery,
  }) : delegate = delegate ?? PangeaVoipDelegate(),
       _tokens = tokenRepo ?? CallTokenRepo(),
       _discovery = focusDiscovery ?? RtcFocusDiscovery();

  /// The focus this homeserver advertises, or null if it advertises none.
  ///
  /// Resolved by fetching `.well-known` rather than reading [Client.wellKnown]:
  /// this app configures its homeserver from its own environment and never calls
  /// `checkHomeserver`, so that field is never populated and reading it would
  /// report calling unavailable everywhere.
  ///
  /// Memoized including the negative answer — a homeserver with no focus is a
  /// deployment fact, not a transient one, and re-asking on every chat screen
  /// would be a request per room opened.
  Future<RtcFocus?> resolveFocus() => _resolving ??= () async {
    final homeserver = client.homeserver;
    _focus = homeserver == null ? null : await _discovery.discover(homeserver);
    return _focus;
  }();

  /// The focus, once [resolveFocus] has answered. Null before that, and null on a
  /// homeserver that advertises none.
  RtcFocus? get focus => _focus;

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
    // The SDK identifies our membership per VoIP instance, so a second join
    // would overwrite the first's identity and leave that call advertised with
    // nobody able to retract it. The claim is taken before the first await, so
    // there is no window for a second caller to pass the same check.
    if (_current != null || _joining) {
      throw StateError('this account is already in a call');
    }
    _joining = true;
    try {
      return await _join(room);
    } finally {
      _joining = false;
    }
  }

  Future<CallToken> _join(Room room) async {
    final f = await resolveFocus();
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

  /// Announces this device as a participant, so the peer sees us in the call.
  ///
  /// Separate from [join] because the two are not simultaneous by design: media
  /// comes up in between, so a peer never sees a participant who cannot yet be
  /// heard.
  Future<void> announce() async => _current?.enter();

  /// Retracts our membership and tears the session down.
  ///
  /// The session is released only once leaving has actually succeeded. Clearing
  /// it first would discard the only handle able to retry, so a failed retract
  /// would leave the membership advertised with nothing left that could take it
  /// back.
  ///
  /// Idempotent and safe to race: concurrent callers join the same attempt
  /// rather than each sending their own leave.
  Future<void> retract() => _retracting ??= () async {
    try {
      await _current?.leave();
      _current = null;
    } finally {
      _retracting = null;
    }
  }();

  /// Tears the service down, retracting any membership it still holds.
  ///
  /// Dropping the session instead would leave this account advertised in a call
  /// until the state event expired, with nothing left able to retract it —
  /// account teardown reaches here while a call can still be live.
  Future<void> dispose() async {
    try {
      await retract();
    } catch (e, s) {
      Logs().w('Could not retract the call membership during teardown', e, s);
    }
    _tokens.close();
    _discovery.close();
    _voip = null;
    _focus = null;
    _resolving = null;
  }

  @visibleForTesting
  bool get hasJoinedSession => _current != null;

  @visibleForTesting
  bool get voipConstructed => _voip != null;
}
