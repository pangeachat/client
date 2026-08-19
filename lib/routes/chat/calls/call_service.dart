import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/pangea_voip_delegate.dart';
import 'package:fluffychat/routes/chat/calls/rtc_focus.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

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

  /// Stops work that an account teardown has overtaken.
  ///
  /// Every await here is a place a logout can land, and resuming afterwards
  /// rebuilds the very things dispose has just released — above all the SDK's
  /// VoIP instance, whose listeners then outlive the client. Calling this after
  /// each await is what keeps that impossible, rather than remembering to check
  /// at the sites somebody happened to review.
  void _stopIfDisposed() {
    if (_disposed) {
      throw StateError('the call service was disposed');
    }
  }

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

  /// The in-flight announce. Retracting waits for it, so a leave can never be
  /// sent before the join it is undoing.
  Future<void>? _entering;

  /// Set when a leave was given up on. The session is released either way — a
  /// learner must not be locked out of calling by a failure they cannot see —
  /// but the caller is told, so a teardown that did not actually take the
  /// membership back is never recorded as clean.
  bool _abandonedMembership = false;

  CallService(
    this.client, {
    PangeaVoipDelegate? delegate,
    CallTokenRepo? tokenRepo,
    RtcFocusDiscovery? focusDiscovery,
    Duration? joinWithin,
  }) : delegate = delegate ?? PangeaVoipDelegate(),
       _tokens = tokenRepo ?? CallTokenRepo(),
       _discovery = focusDiscovery ?? RtcFocusDiscovery(),
       _joinWithin = joinWithin ?? const Duration(seconds: 30);

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

  /// How long leaving waits for a join that has not landed. Past this the leave
  /// goes anyway: the membership expires by itself, and holding the microphone
  /// open is the worse outcome.
  static const _settleEnterWithin = Duration(seconds: 5);

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
  VoIP get voip => _voip ??= VoIP(client, delegate);

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
    // A call whose leave was given up on is not live — nothing has been able to
    // retract it — so it must never block a new one. This is what makes it safe
    // to KEEP that session rather than release it: releasing it was how a later
    // retry came to find nothing and report a success it had not achieved.
    if (_abandonedMembership && _current != null) {
      Logs().w('Discarding a call whose membership could not be retracted');
      _current = null;
      _abandonedMembership = false;
    }
    if (_current != null || _joining) {
      throw StateError('this account is already in a call');
    }
    _joining = true;
    final attempt = ++_joinAttempt;
    try {
      // Bounded, because this claim is what stands between the account and
      // every other call it could make or take. Three round-trips happen inside
      // it — focus discovery, the session, the token — and any of them can hang
      // on a bad network. Held for good, the claim suppressed every incoming
      // ring and refused every new call until the app was restarted, with no
      // way to release it: a hangup cannot give back a call that never arrived.
      return await _join(room, attempt).timeout(_joinWithin);
    } on TimeoutException {
      // Whatever is still in flight belongs to nobody now, so it must not
      // install itself as this account's call when it finally lands.
      _joinAttempt++;
      Logs().w('Gave up joining the call; it took too long to come up');
      rethrow;
    } finally {
      _joining = false;
    }
  }

  /// How long the whole join may take before it is treated as failed. Injected
  /// so a test can prove the claim is released without waiting out the real one.
  final Duration _joinWithin;

  /// Gives up a join this account no longer wants.
  ///
  /// Hanging up while a call is still coming up used to leave the claim held
  /// until the network finally answered — up to the whole join timeout — and
  /// for that long every incoming ring was suppressed and every new call
  /// refused, with the screen already closed. Anything still in flight is
  /// disowned so it cannot install itself afterwards.
  void abandonJoin() {
    if (!_joining) return;
    _joinAttempt++;
    _joining = false;
    Logs().i('Gave up a join the user no longer wants');
  }

  /// Whether a join that was given up on should hand its session back.
  ///
  /// It must not, when anyone else could be using it. The session is fetched by
  /// ROOM — one direct message holds at most one call — so a later attempt in
  /// the same room is handed this very object, and leaving it would retract the
  /// call that is actually up. That is worse than the leak it was meant to
  /// prevent: a membership left behind expires by itself in minutes, while a
  /// live call cut off is a conversation dropped.
  ///
  /// [joinInFlight] covers the attempt that has not claimed the session yet:
  /// it will, and it will apply this same rule if it is abandoned in turn.
  @visibleForTesting
  static bool releasesAbandonedSession({
    required bool joinInFlight,
    required bool isCurrent,
  }) => !joinInFlight && !isCurrent;

  /// Which join is the live one. A join that was given up on keeps running —
  /// there is no cancelling a request in flight — so it is told apart by this
  /// rather than left to install itself over the top of whatever came after.
  int _joinAttempt = 0;

  Future<CallToken> _join(Room room, int attempt) async {
    final f = await resolveFocus();
    // Before anything is constructed: discovery is a network round-trip and the
    // account can log out inside it.
    _stopIfDisposed();
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

    final isCurrent = identical(session, _current);
    if (_disposed || attempt != _joinAttempt) {
      // The account went away while this join was in flight, or the join itself
      // was given up on. Storing the session now would advertise a membership
      // that nothing is left to retract, and it would stand until it expired
      // minutes later.
      if (releasesAbandonedSession(
        joinInFlight: _joining,
        isCurrent: isCurrent,
      )) {
        try {
          await session.leave();
        } catch (e, st) {
          Logs().w('Could not leave a call abandoned during teardown', e, st);
        }
      }
      throw StateError('the call was abandoned while joining');
    }

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

  /// Whether the caller is still in the call in [room] — a live membership from
  /// a user other than this account.
  ///
  /// Keyed on another USER, not this account, so this device's own stale
  /// membership from a failed retract cannot make a real incoming call look
  /// like a call of one. Checked before answering, so a caller who gave up is
  /// not joined.
  bool otherUserInCall(Room room) {
    final me = client.userID;
    if (me == null || _disposed) return false;
    return room
        .getCallMembershipsFromRoom(voip)
        .values
        .expand((list) => list)
        .any((m) => m.userId != me && !m.isExpired);
  }

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

  /// Whether THIS device is already in a call, anywhere.
  ///
  /// The local session, not room state — so a stale membership a failed retract
  /// left behind does not read as busy and silence the next incoming call, and
  /// a call genuinely in progress does suppress a second ring.
  /// Includes the join in flight, not just [_current]: a call is claimed by
  /// [_joining] before the session exists, and a ring arriving in that window
  /// would show a prompt whose answer could only fail when the second join is
  /// refused.
  bool get isBusy => _current != null || _joining;

  /// Fires when participants join or leave the current call.
  Stream<MatrixRTCCallEvent>? get callEvents =>
      _current?.matrixRTCEventStream.stream;

  /// Rings the other side, and returns the notification's event id.
  ///
  /// A timeline event rather than relying on membership: membership is room
  /// state, and state changes do not fire push rules, so a learner whose app was
  /// closed would never learn they were called. This is what push delivers.
  ///
  /// Referenced to our own membership event, per MSC4075 — that is how a
  /// receiver knows which call it is, and it is what a decline points back at.
  /// Null if our membership is not yet in room state, in which case the call
  /// still works, it just does not ring: better silent than crashing.
  Future<String?> ring(
    Room room, {
    required String membershipEventId,
    required bool video,
  }) async {
    // One transaction id across both attempts. A send whose response is lost may
    // already have reached the server, and the ring's id is what a decline
    // points back at — without it the caller sits through the whole ring and
    // records the call as unanswered when it was turned down. Reusing the id
    // makes the server hand back the event the first attempt created.
    final txid = 'pangea.call.ring.$membershipEventId';
    final content = CallNotification(
      membershipEventId: membershipEventId,
      senderDeviceId: client.deviceID!,
      video: video,
    ).toContent(DateTime.now());

    // If both attempts lose their response while the event itself lands, the
    // caller never learns its id and a decline cannot be matched to it: the call
    // rings out and is recorded as unanswered rather than turned down. That is
    // accepted. The alternative — treating any decline in the room as this
    // call's — was tried and ended calls that had only just started, twice.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await room.sendEvent(
          content,
          type: PangeaEventTypes.callNotification,
          txid: txid,
        );
      } catch (e, s) {
        Logs().w(
          'Could not ring the other side (attempt ${attempt + 1})',
          e,
          s,
        );
      }
    }
    return null;
  }

  /// Our own membership's event id in [room]'s current call, or null.
  ///
  /// Read again at the end of a call by a device that had none: the wait when
  /// announcing is deliberately short so a caller is never left hanging, and a
  /// device that joined a call already under way has nothing else to anchor its
  /// analytics to.
  String? membershipEventIdIn(Room room) {
    // Answered only while the machinery that tracked the call is still here.
    // Reading a membership goes through the SDK's VoIP instance, and asking
    // after teardown would BUILD one — listeners and all — to answer a question
    // about a call that no longer exists.
    if (_disposed || _voip == null || _current == null) return null;
    return _myMembershipEventId(room);
  }

  String? _myMembershipEventId(Room room) {
    for (final m in room.getCallMembershipsForUser(
      client.userID!,
      client.deviceID!,
      voip,
    )) {
      if (m.callId == _current?.groupCallId && !m.isExpired) return m.eventId;
    }
    return null;
  }

  /// Calls arriving for this account, decided from the notification event.
  ///
  /// Replaces ringing off membership discovery: a notification is a timeline
  /// event, so it arrives the same way whether the app was open or woken by a
  /// push, and it carries how long to ring and which call it is.
  Stream<IncomingCallNotification> get incomingRings => client
      .onTimelineEvent
      .stream
      .where(
        (event) =>
            event.type == PangeaEventTypes.callNotification &&
            event.room.isDirectChat,
      )
      .map(
        (event) => IncomingCallNotification(
          event: event,
          myUserId: client.userID ?? '',
          // Busy is read from the local session, so this device's own stale
          // membership never suppresses a real incoming call, while a call
          // genuinely in progress does.
          alreadyJoined: isBusy,
        ),
      )
      .where((ring) => ring.shouldRing(DateTime.now()));

  /// Turns down the call [notification] announced, telling its caller.
  ///
  /// Points back at the notification event, per MSC4310, so the caller matches
  /// the decline to the exact call they rang rather than to the room.
  Future<void> decline(Room room, {required String notificationEventId}) async {
    try {
      await room.sendEvent({
        'msgtype': PangeaEventTypes.callDecline,
        'body': '',
        'm.relates_to': {
          'rel_type': 'm.reference',
          'event_id': notificationEventId,
        },
      }, type: PangeaEventTypes.callDecline);
    } catch (e, s) {
      Logs().w('Could not tell the caller the call was declined', e, s);
    }
  }

  /// Ring notifications sent by someone else in [room].
  ///
  /// Used to notice that the other person is calling us at the same moment we
  /// are calling them, which decides which side writes the call to the room.
  Stream<Event> ringsIn(Room room) => client.onTimelineEvent.stream.where(
    (event) =>
        event.room.id == room.id &&
        event.type == PangeaEventTypes.callNotification &&
        event.senderId != client.userID,
  );

  /// Every decline sent by someone else in [room].
  ///
  /// Deliberately not filtered to one call: a caller has to be listening before
  /// its own ring has finished sending, which is before it knows the id a
  /// decline would point at. Matching is the caller's job.
  Stream<Event> declinesIn(Room room) => client.onTimelineEvent.stream.where(
    (event) =>
        event.room.id == room.id &&
        event.type == PangeaEventTypes.callDecline &&
        event.senderId != client.userID,
  );

  /// This account joining a call, on whichever device.
  ///
  /// Read from room state rather than from the local session, because the whole
  /// point is to hear about a DIFFERENT device. The membership is written by
  /// whoever answers, so a phone still ringing learns the call was picked up
  /// and can put its prompt away.
  ///
  /// Deliberately not routed through the SDK's VoIP helpers: asking those would
  /// build a VoIP instance — listeners, a scan of every joined room — on a
  /// device that is not in a call. A leave writes empty content, which is why
  /// presence is read from the content rather than from the event existing.
  Stream<String> ownCallJoins() => client.onRoomState.stream
      .where(
        (update) =>
            update.state.type == EventTypes.GroupCallMember &&
            (update.state.stateKey?.contains(client.userID ?? '\u0000') ??
                false) &&
            update.state.content.isNotEmpty,
      )
      .map((update) => update.roomId);

  /// Declines this account sent, from any of its devices.
  ///
  /// The mirror of [declinesIn], which deliberately leaves them out: a caller
  /// must never be hung up by its own decline. A device that is still ringing is
  /// the opposite case — somebody has answered this call on another phone, and
  /// this one should stop offering to answer it.
  Stream<Event> ownDeclines() => client.onTimelineEvent.stream.where(
    (event) =>
        event.type == PangeaEventTypes.callDecline &&
        event.senderId == client.userID,
  );

  /// The notification a decline points back at, or null if it points at nothing.
  String? declineTarget(Event event) => _declineRefersTo(event);

  String? _declineRefersTo(Event event) {
    final relation = event.content['m.relates_to'];
    if (relation is! Map || relation['rel_type'] != 'm.reference') return null;
    final id = relation['event_id'];
    return id is String ? id : null;
  }

  /// Announces this device as a participant, so the peer sees us in the call.
  ///
  /// Separate from [join] because the two are not simultaneous by design: media
  /// comes up in between, so a peer never sees a participant who cannot yet be
  /// heard.
  Future<String?> announce() async {
    _stopIfDisposed();
    final session = _current;
    if (session == null) return null;
    // A leave that failed part-way can leave the SDK's session still entered,
    // and it is reused by the next join. Entering it again throws, which would
    // make every later call in that room fail for a transient error the learner
    // never saw. Already-entered is the state we wanted.
    if (session.state != GroupCallState.entered &&
        session.state != GroupCallState.entering) {
      // Held so a retract cannot overtake it. Leaving while the enter write is
      // still in flight let that write land afterwards, advertising a
      // membership with nothing left tracking it — and this SDK's memberships
      // stand for minutes.
      final entering = _entering = session.enter();
      try {
        await entering;
      } finally {
        if (identical(_entering, entering)) _entering = null;
      }
    }
    return _awaitMembershipEventId(session.room);
  }

  /// Our own membership's event id, waiting briefly for the state write to echo.
  ///
  /// `enter()` writes the membership but does not return its id, and the id only
  /// appears in room state once the write echoes back. The ring references it,
  /// so a blank wait would mean the call connects but never rings — the receiver
  /// would be woken by nothing. Bounded: a caller must not hang because an echo
  /// is slow, so after the window the call proceeds unrung rather than stuck.
  Future<String?> _awaitMembershipEventId(Room room) async {
    for (var attempt = 0; attempt < 15; attempt++) {
      // Three seconds of polling is ample time for a logout to land, and every
      // read here reaches through the VoIP getter — which would rebuild the
      // instance dispose had just dropped.
      _stopIfDisposed();
      final id = _myMembershipEventId(room);
      if (id != null) return id;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _stopIfDisposed();
    Logs().w('Membership event id did not appear; the call will not ring');
    return null;
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
      if (session == null) return !_abandonedMembership;
      // Never leave before the enter it undoes has landed — but not for ever.
      // Everything after this frees the microphone and the camera, so a join
      // that is stuck would otherwise leave them open for as long as it hung.
      try {
        await _entering?.timeout(_settleEnterWithin);
      } catch (_) {}
      // Retried here, holding the session, because releasing it first left
      // nothing to retry WITH — a later attempt would find nothing to leave and
      // report success it had not achieved. The SDK's own leave() also stops
      // short of cleaning up when its first write throws, so the same session is
      // what a retry has to reach.
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          if (attempt > 0) await Future.delayed(Duration(seconds: attempt));
          await session.leave();
          _abandonedMembership = false;
          return true;
        } catch (e, s) {
          Logs().w('Retracting the call membership failed', e, s);
        }
      }
      // Given up on. The membership expires by itself, and holding the session
      // forever would refuse every later call over a failure the learner can
      // neither see nor act on.
      Logs().w('Gave up retracting the membership; it will expire');
      _abandonedMembership = true;
      return false;
    } finally {
      // Released only when the membership was actually taken back. Keeping a
      // session whose leave failed is what gives a later attempt something to
      // retry WITH; a new call is not blocked by it, because join discards it.
      if (!_abandonedMembership) _current = null;
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

    _focusRetry?.cancel();
    _focusRetry = null;
    try {
      await retract();
    } catch (e, s) {
      Logs().w('Could not retract the call membership during teardown', e, s);
    }
    _tokens.close();
    _discovery.close();
    // The SDK's VoIP has no dispose and its listeners are attached to the
    // client's own streams, so they are torn down when the client is disposed
    // on logout — which is when this runs. Dropping the reference is all this
    // layer can do; the ring and answer paths are the only things that build it,
    // so a receiver that only ever rings never constructs it at all.
    _voip = null;
    _focus = null;
    _resolving = null;
  }

  @visibleForTesting
  bool get hasJoinedSession => _current != null;

  @visibleForTesting
  bool get voipConstructed => _voip != null;
}
