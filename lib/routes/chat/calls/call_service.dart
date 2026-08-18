import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/incoming_call.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
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

  /// Holds a failed lookup for a moment so a retry does not become a flood.
  /// Cancelled on disposal — an untracked one would fire into a service the
  /// account has already logged out of.
  Timer? _focusRetry;

  /// Set before anything is torn down, so work already in flight can see it has
  /// nothing left to schedule.
  bool _disposed = false;

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
  Future<bool>? _retracting;

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
    if (homeserver == null) return null;
    try {
      return _focus = await _discovery.discover(homeserver);
    } catch (e) {
      // Only a definitive answer is remembered, so a blip does not hide the call
      // button for the session. But the chat header asks on every direct room
      // opened, so an outage would otherwise mean a request per room — the
      // failure is held briefly to keep a retry from becoming a flood.
      Logs().d('RTC focus lookup failed, will retry shortly: $e');
      // A lookup already in flight when the account logs out resumes here, so
      // the guard belongs at the point of scheduling, not only in dispose.
      if (_disposed) return null;
      _focusRetry?.cancel();
      _focusRetry = Timer(_retryFocusAfter, () => _resolving = null);
      return null;
    }
  }();

  /// How long a failed lookup is left in place before the next ask retries it.
  static const _retryFocusAfter = Duration(seconds: 30);

  /// Drops a held failure so the next [resolveFocus] asks immediately.
  @visibleForTesting
  void retryFocusNow() => _resolving = null;

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
  VoIP get voip => _voip ??= () {
    // Wired here rather than in the constructor: the callback needs this
    // service, and the delegate must be complete before VoIP dereferences it.
    delegate.onGroupCallDiscovered = _onCallDiscovered;
    return VoIP(client, delegate);
  }();

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

  /// Every device of this account holding a live membership in the current call,
  /// this one included.
  ///
  /// The SDK adds another of your own devices as an ordinary participant — it
  /// excludes only the exact local device from mesh setup — so these come
  /// straight off the session.
  /// Read from room state rather than the session's participant list, because
  /// this has to answer before this device has announced itself — the whole
  /// point is to know whether to record from the first word, and the session
  /// does not list anyone until membership changes have been processed.
  ///
  /// Expired memberships are skipped: a device that crashed stops renewing, and
  /// treating it as present would hand it a recording it cannot make.
  List<String> get myDeviceIdsInCall {
    final session = _current;
    if (session == null) return const [];
    // Every state key, not the one this device's id resolves to. Where a room
    // keys membership per device, asking for "this user's key" returns only this
    // device — and every device would then believe it was alone and record.
    return [
      for (final memberships
          in session.room.getCallMembershipsFromRoom(voip).values)
        for (final m in memberships)
          if (m.userId == client.userID &&
              m.callId == session.groupCallId &&
              !m.isExpired)
            m.deviceId,
    ];
  }

  /// Calls arriving for this account that it is not already in.
  ///
  /// The SDK reports every call it discovers, including this device's own and
  /// including ones everyone has left, so the decision is made here rather than
  /// treating discovery as a ring.
  Stream<Room> get incomingCalls => _incoming.stream;

  /// Starts watching for calls arriving for this account.
  ///
  /// Receiving a call requires the SDK's VoIP to exist — it is what notices a
  /// membership appearing — and that is built lazily, on placing a call. Without
  /// this, an account that had never called could never be called: nothing was
  /// listening.
  Future<void> listenForCalls() async {
    if (_disposed || isListening) return;
    // A homeserver with no focus cannot carry calls, so there is nothing to
    // listen for and no reason to pay for VoIP's scan of every joined room.
    if (await resolveFocus() != null) {
      if (_disposed) return;
      voip; // Constructing it is what arms discovery.
      return;
    }
    if (_disposed || _focus != null) return;

    // The lookup did not answer. Left here, an account that hit one bad moment
    // at startup would never ring again for the rest of the session — so it
    // tries again rather than deciding it cannot be called.
    _armRetry?.cancel();
    _armRetry = Timer(_retryFocusAfter, () {
      _resolving = null;
      unawaited(listenForCalls());
    });
  }

  Timer? _armRetry;

  /// Whether this account can be called: it has a focus and is listening.
  bool get isListening => _voip != null;
  final StreamController<Room> _incoming = StreamController<Room>.broadcast();

  void _onCallDiscovered(GroupCallSession session) {
    if (_disposed) return;
    // Direct messages only, matching where the call button is offered. A group
    // room with a live call would otherwise ring every member of this app.
    if (!session.room.isDirectChat) return;
    if (isRinging(session.room)) _incoming.add(session.room);
  }

  /// Whether a call in [room] is still waiting for this account to answer.
  ///
  /// Asked again while a prompt is showing, because a caller can give up: a
  /// banner that only ever appeared would ring for a room nobody is calling
  /// from, and answering it would join a call of one.
  bool isRinging(Room room) {
    final me = client.userID;
    if (me == null || _disposed) return false;
    return IncomingCall(
      memberships: [
        for (final list in room.getCallMembershipsFromRoom(voip).values)
          ...list,
      ],
      myUserId: me,
    ).shouldRing;
  }

  /// [isRinging] by room id, for a caller that holds an id rather than a room.
  bool isRingingIn(String roomId) {
    final room = client.getRoomById(roomId);
    return room != null && isRinging(room);
  }

  /// Tells the caller their call was turned down.
  ///
  /// Sent to the room rather than kept local, because a decline that only
  /// dismissed a banner would leave the caller ringing at someone who has
  /// already said no — which is what every other calling app avoids, and what
  /// MSC4310 exists to fix.
  Future<void> decline(Room room) async {
    try {
      await room.sendEvent({
        'msgtype': PangeaEventTypes.callDecline,
        'body': '',
      }, type: PangeaEventTypes.callDecline);
    } catch (e, s) {
      // The learner's own side is already dismissed; failing to tell the caller
      // costs them a few more seconds of ringing, not the decline.
      Logs().w('Could not tell the caller the call was declined', e, s);
    }
  }

  /// Fires when someone other than this account turns down a call in [room].
  Stream<Event> declinesIn(Room room) => client.onTimelineEvent.stream.where(
    (event) =>
        event.roomId == room.id &&
        event.type == PangeaEventTypes.callDecline &&
        event.senderId != client.userID,
  );

  /// Whether anyone other than this account is still in the call.
  ///
  /// A direct-message call is over when the other person leaves; there is nobody
  /// left to talk to, and staying would hold a microphone open for a
  /// conversation that has ended.
  bool get hasRemoteParticipants {
    final session = _current;
    if (session == null) return false;
    return session.participants.any((p) => p.userId != client.userID);
  }

  /// Fires when participants join or leave the current call.
  Stream<MatrixRTCCallEvent>? get callEvents =>
      _current?.matrixRTCEventStream.stream;

  /// Announces this device as a participant, so the peer sees us in the call.
  ///
  /// Separate from [join] because the two are not simultaneous by design: media
  /// comes up in between, so a peer never sees a participant who cannot yet be
  /// heard.
  Future<void> announce() async {
    final session = _current;
    if (session == null) return;
    // A leave that failed part-way can leave the SDK's session still entered,
    // and it is reused by the next join. Entering it again throws, which would
    // make every later call in that room fail for a transient error the learner
    // never saw. Already-entered is the state we wanted.
    if (session.state == GroupCallState.entered ||
        session.state == GroupCallState.entering) {
      Logs().i('Call session is already entered; not entering again');
      return;
    }
    await session.enter();
  }

  /// Retracts our membership and tears the session down.
  ///
  /// The session is released only once leaving has actually succeeded. Clearing
  /// it first would discard the only handle able to retry, so a failed retract
  /// would leave the membership advertised with nothing left that could take it
  /// back.
  ///
  /// Idempotent and safe to race: concurrent callers join the same attempt
  /// rather than each sending their own leave.
  /// Returns whether the membership was actually taken back.
  ///
  /// The session is released either way: the membership expires on its own, and
  /// refusing every future call to preserve a retry nothing will invoke would
  /// lock the learner out of calling over a failure they cannot see. But the
  /// caller is told, because silently reporting success meant the one retry that
  /// could have helped never happened.
  Future<bool> retract() => _retracting ??= () async {
    final session = _current;
    try {
      if (session == null) return true;
      // Retried here, holding the session, because releasing it first left
      // nothing to retry WITH — a later attempt would find nothing to leave and
      // report success it had not achieved. The SDK's own leave() also stops
      // short of cleaning up when its first write throws, so the same session is
      // what a retry has to reach.
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          if (attempt > 0) await Future.delayed(Duration(seconds: attempt));
          await session.leave();
          return true;
        } catch (e, s) {
          Logs().w('Retracting the call membership failed', e, s);
        }
      }
      // Given up on. The membership expires by itself, and holding the session
      // forever would refuse every later call over a failure the learner can
      // neither see nor act on.
      Logs().w('Gave up retracting the membership; it will expire');
      return false;
    } finally {
      _current = null;
      _retracting = null;
    }
  }();

  /// Tears the service down, retracting any membership it still holds.
  ///
  /// Dropping the session instead would leave this account advertised in a call
  /// until the state event expired, with nothing left able to retract it —
  /// account teardown reaches here while a call can still be live.
  Future<void> dispose() async {
    _disposed = true;
    // Cleared before the stream closes: the SDK's own listeners outlive this
    // service, and a late discovery would otherwise add to a closed controller.
    delegate.onGroupCallDiscovered = null;
    unawaited(_incoming.close());
    _focusRetry?.cancel();
    _focusRetry = null;
    _armRetry?.cancel();
    _armRetry = null;
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
