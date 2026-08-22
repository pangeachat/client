import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_breadcrumb.dart';
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
    Duration? leaveWithin,
  }) : delegate = delegate ?? PangeaVoipDelegate(),
       _tokens = tokenRepo ?? CallTokenRepo(),
       _discovery = focusDiscovery ?? RtcFocusDiscovery(),
       _joinWithin = joinWithin ?? const Duration(seconds: 30),
       _leaveWithin = leaveWithin ?? const Duration(seconds: 3);

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

  /// How long announcing this device's membership may take. Generous, because
  /// it is a state write plus its echo, and giving up costs the call.
  static const _announceWithin = Duration(seconds: 20);

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
      throw const AlreadyInACall();
    }
    _joining = true;
    final attempt = ++_joinAttempt;
    // Before anything is fetched. A leave still in flight from the last call
    // holds this room's session, and starting over the top of it means the new
    // membership is published into a session that is about to be left.
    await settlePendingLeave();
    try {
      // Bounded, because this claim is what stands between the account and
      // every other call it could make or take. Three round-trips happen inside
      // it — focus discovery, the session, the token — and any of them can hang
      // on a bad network. Held for good, the claim suppressed every incoming
      // ring and refused every new call until the app was restarted, with no
      // way to release it: a hangup cannot give back a call that never arrived.
      return await _join(room, attempt).timeout(_joinWithin);
    } on TimeoutException {
      // Released here rather than left to the guard below, which by then would
      // see the bumped attempt and decline to touch a claim this call still
      // owns. Whatever is still in flight belongs to nobody now, so it must not
      // install itself as this account's call when it finally lands.
      _joining = false;
      _joinAttempt++;
      Logs().w('Gave up joining the call; it took too long to come up');
      rethrow;
    } finally {
      // Only if this attempt still owns the claim. A later join takes it over
      // when this one has been given up on, and clearing it then reported the
      // account free while that newer join was still in flight — so a third
      // call could start on top of it.
      if (attempt == _joinAttempt) _joining = false;
    }
  }

  /// How long one attempt to ring may take. Two attempts, so the caller waits
  /// at most twice this before the call gets on with ringing out.
  static const _ringWithin = Duration(seconds: 10);

  /// A leave that was given up on but is still running. The next call in this
  /// room waits for it rather than racing it.
  Future<void>? _leaving;

  /// Records a leave still in flight, and forgets it the moment it finishes —
  /// never before.
  ///
  /// The clearing is tied to the leave's OWN completion, not to any waiter
  /// giving up on it. A waiter that cleared it on timeout let the next call stop
  /// waiting for a leave still running, and — because the session is fetched by
  /// room, so a redial lands on the very object that leave still holds — the
  /// next call would then publish its membership straight into a session this
  /// leave is about to retract.
  void _setPendingLeave(Future<void> leaving) {
    _leaving = leaving;
    unawaited(
      leaving
          .whenComplete(() {
            if (identical(_leaving, leaving)) _leaving = null;
          })
          .catchError((Object _, StackTrace _) {}),
    );
  }

  /// Waits for a leave that was given up on to actually finish.
  ///
  /// Bounded: waiting longer would hold up a call the learner is asking for now,
  /// so after the window the call goes ahead. But the pending leave is NOT let
  /// go of here — it clears itself when it completes — so every call that starts
  /// while it is still running waits for it in turn rather than racing it. That
  /// is the whole protection against a stale leave retracting a fresh call's
  /// membership; dropping it on the first timeout threw that protection away for
  /// every call after.
  @visibleForTesting
  Future<void> settlePendingLeave() async {
    final leaving = _leaving;
    if (leaving == null) return;
    Logs().i('Waiting for the last call to finish leaving');
    try {
      await leaving.timeout(_leaveWithin);
    } catch (_) {
      // Waited as long as is reasonable; the leave keeps running and is
      // forgotten only when it finishes, not here.
    }
  }

  /// Puts a still-running leave in place, for tests.
  @visibleForTesting
  void setPendingLeaveForTest(Future<void> leaving) =>
      _setPendingLeave(leaving);

  /// Whether a leave is still being waited for. For tests.
  @visibleForTesting
  bool get hasPendingLeaveForTest => _leaving != null;

  /// Numbers each ring this session sends, so two calls sharing a membership
  /// cannot share a transaction id.
  int _ringSeq = 0;

  String? _lastRingTxid;

  /// The transaction id of the ring just sent, for tests.
  @visibleForTesting
  String? get debugLastRingTxidForTest => _lastRingTxid;

  /// How long one attempt to take the membership back may take.
  final Duration _leaveWithin;

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
  void abandonJoin(int attempt) {
    // Only the attempt that made the claim may give it up. A call refused
    // because this account was already joining never held it, and cancelling on
    // its way out took down somebody else's join in flight.
    if (!_joining || attempt != _joinAttempt) return;
    _joinAttempt++;
    _joining = false;
    Logs().i('Gave up a join the user no longer wants');
  }

  /// Which join attempt is current. A caller keeps this so it can give up its
  /// OWN join later, and nobody else's.
  int get joinAttempt => _joinAttempt;

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
  bool get isBusy => busyFrom(
    hasSession: _current != null,
    abandoned: _abandonedMembership,
    joining: _joining,
  );

  /// Whether this account is in a call, for the purpose of refusing new ones and
  /// suppressing rings.
  ///
  /// A session whose membership could not be taken back does NOT count. It is
  /// kept only so a later attempt has something to retry with — nothing is live,
  /// and the membership expires by itself. Counted, it went on suppressing every
  /// incoming ring, so the learner simply stopped receiving calls until they
  /// happened to place one themselves.
  @visibleForTesting
  static bool busyFrom({
    required bool hasSession,
    required bool abandoned,
    required bool joining,
  }) => (hasSession && !abandoned) || joining;

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
    // One transaction id across both attempts, and a different one for every
    // call. A send whose response is lost may already have reached the server,
    // and the ring's id is what a decline points back at — without it the caller
    // sits through the whole ring and records the call as unanswered when it was
    // turned down. Reusing the id makes the server hand back the event the first
    // attempt created.
    //
    // The membership alone is not enough to name a call. A retract that failed
    // leaves the membership in place and the next call in that room reuses it,
    // so the two calls would ring with the SAME transaction id: the server hands
    // back the FIRST call's ring, and a decline of that one — long since sent —
    // marks the new call as turned down. A decline landing on the wrong call has
    // been paid for twice already.
    //
    // The counter is NOT enough on its own. It lives on this service, so a page
    // reload or an app restart begins again at one -- and the membership event
    // id is reused whenever a join finds a membership already standing. The two
    // together then rebuild a transaction id this account has ALREADY used, the
    // homeserver recognises it, hands back the original ring and writes nothing.
    // The callee's phone never rings, while the caller sits through the full
    // lifetime and records a missed call. Measured on a live server: every ring
    // id was being sent exactly twice, the second creating no event at all.
    //
    // The moment of sending is what makes it unrepeatable, and it is taken once
    // here rather than per attempt, so the retry below still asks for the same
    // event rather than ringing twice.
    final txid = _lastRingTxid =
        'pangea.call.ring.$membershipEventId.${++_ringSeq}'
        '.${DateTime.now().microsecondsSinceEpoch}';
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
        // Bounded, like every other network step in a call's life. Coming up
        // waits for this before it starts the clock on somebody answering, and
        // the record waits for coming up — so a send that never came back left
        // the call ringing for ever and never wrote it down. A send that times
        // out may still have landed, which is what the stable transaction id
        // above is for: the retry gets the same event back rather than ringing
        // twice.
        return await room
            .sendEvent(
              content,
              type: PangeaEventTypes.callNotification,
              txid: txid,
            )
            .timeout(_ringWithin);
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
      .where(_worthRinging);

  /// Whether a notification should raise a prompt, saying so out loud when it
  /// should not.
  ///
  /// A ring dropped here leaves NO trace otherwise: the caller still rings out
  /// and still writes a missed-call card, so the room shows a call that the
  /// callee's screen never mentioned. That is indistinguishable, from the
  /// outside, from the notification never arriving -- which is what made this
  /// class of bug so hard to place.
  bool _worthRinging(IncomingCallNotification ring) {
    final now = DateTime.now();
    if (ring.shouldRing(now)) return true;
    // ONLY the busy case. Everything else a ring can fail on — expired, not a
    // ring, our own, naming no call — is ordinary traffic and says nothing
    // surprising. Being busy is the one where a real call reached this device
    // and was dropped anyway, leaving the caller to write a missed-call card
    // for a prompt that never appeared.
    //
    // Nothing here may throw: this runs inside a stream predicate, where an
    // error would take the ring stream down and stop the account receiving
    // calls at all. Only fields already parsed by shouldRing are read.
    try {
      // Busy must be the SOLE reason. Every other predicate of shouldRing is
      // required to pass here, or an expired or nameless ring that happens to
      // arrive while busy would be reported as suppressed by busy, and send the
      // next person reading this log after the wrong thing.
      final onlyBusy =
          ring.alreadyJoined &&
          ring.isCall &&
          ring.isRing &&
          ring.event.senderId != client.userID &&
          ring.membershipEventId != null &&
          !ring.hasExpiredBy(now);
      if (onlyBusy) {
        Logs().i(
          'Not ringing for ${ring.event.eventId} in ${ring.event.room.id}: '
          'this account reads as being in a call',
        );
        // And TELL them. Suppressing the ring in silence left the caller
        // listening to nothing until the ring timed out, and then wrote it
        // in their history as a call nobody answered -- when the truth is
        // that the line was busy. The decline goes back at once, carrying
        // the reason, so their screen can say so and stop.
        unawaited(
          decline(
            ring.event.room,
            notificationEventId: ring.event.eventId,
            reason: declineBusy,
          ),
        );
      }
    } catch (_) {
      // A diagnostic is never worth a dropped call.
    }
    return false;
  }

  /// Turns down the call [notification] announced, telling its caller.
  ///
  /// Points back at the notification event, per MSC4310, so the caller matches
  /// the decline to the exact call they rang rather than to the room.
  /// The reason a decline carries, when there is one worth carrying.
  ///
  /// A person saying no and a device that CANNOT take the call are different
  /// facts, and the caller deserves the difference: one is "they turned you
  /// down", the other is "they are on another call". Absent on an ordinary
  /// decline, so older clients and older events read exactly as before.
  static const declineReasonField = 'reason';
  static const declineBusy = 'busy';

  Future<void> decline(
    Room room, {
    required String notificationEventId,
    String? reason,
  }) async {
    try {
      await room.sendEvent({
        'msgtype': PangeaEventTypes.callDecline,
        'body': '',
        declineReasonField: ?reason,
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

  /// Declines this account sent, from any of its devices.
  ///
  /// The mirror of [declinesIn], which deliberately leaves them out: a caller
  /// must never be hung up by its own decline. A device that is still ringing is
  /// the opposite case — somebody has turned this call down on another phone,
  /// and this one should stop offering to answer it.
  ///
  /// A decline is the only signal used for this. Answering elsewhere writes a
  /// membership, and reading THAT would silence real calls: a device that
  /// crashed leaves one behind that reads as live for about twelve minutes,
  /// which is why this feature does not use membership for liveness anywhere.
  /// The cost is a prompt that lingers on a second device until the ring lapses;
  /// it cannot end the answered call, because a caller ignores a decline once
  /// somebody is on the line.
  Stream<Event> ownDeclines() => client.onTimelineEvent.stream.where(
    (event) =>
        event.type == PangeaEventTypes.callDecline &&
        event.senderId == client.userID,
  );

  /// Whether [callerId] still claims a place in a call in [room].
  ///
  /// A caller who gives up before anybody answers sends nothing to say so —
  /// retracting the membership is the whole of it — so the absence of that
  /// membership is what tells a ringing device to stop offering a call nobody
  /// is on the other end of.
  ///
  /// Read as room STATE, never accumulated from events, and only for PRESENCE.
  /// Expiry is deliberately not read: a caller whose device died leaves a
  /// membership that reads live for minutes, and the ring's own lifetime is
  /// what bounds that case. Reading expiry here would restate SDK rules for no
  /// gain and drift from them.
  ///
  /// Matched on the state event's SENDER rather than its state key, because the
  /// key has three shapes across MSC3757 and per-device variants and only the
  /// sender is the same in all of them.
  bool callerStillInCall(Room room, String callerId) {
    final memberStates = room.states[EventTypes.GroupCallMember];
    if (memberStates == null) return false;
    for (final state in memberStates.values) {
      if (state.senderId != callerId) continue;
      final memberships = state.content['memberships'];
      if (memberships is List && memberships.isNotEmpty) return true;
    }
    return false;
  }

  /// Whether [peerId] still holds a LIVE membership in the call this device
  /// is on.
  ///
  /// Deliberately narrower than [callerStillInCall], which answers "does this
  /// user claim a place in any call here" and is right for deciding whether a
  /// RINGING call still has a caller. This one decides whether a peer has
  /// LEFT the call in progress.
  ///
  /// EXPIRY is what does the work. The call id is the ROOM id by design --
  /// one direct message holds one live call -- so matching on it separates
  /// rooms, not calls, and a room accumulates a membership state event per
  /// device that keeps reading non-empty long after its call ended. Only a
  /// membership still being renewed belongs to somebody who is still here.
  ///
  /// Answers true when it cannot tell (no call of our own to compare
  /// against): the caller treats that as "no opinion" and falls back to the
  /// SFU, which is the pre-existing behaviour.
  /// Pins the call id these reads compare against, for tests that cannot
  /// stand up a real group call session.
  @visibleForTesting
  void adoptCallIdForTest(String callId) => _callIdForTest = callId;

  String? _callIdForTest;

  bool peerLiveInCurrentCall(Room room, String peerId) {
    final callId = _current?.groupCallId ?? _callIdForTest;
    if (callId == null) return true;
    final states = room.states[EventTypes.GroupCallMember];
    if (states == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    var sawAnyOfTheirs = false;
    for (final state in states.values) {
      if (state.senderId != peerId) continue;
      final memberships = state.content['memberships'];
      if (memberships is! List) continue;
      for (final m in memberships) {
        if (m is! Map) continue;
        if (m['call_id'] != callId) continue;
        sawAnyOfTheirs = true;
        final expires = m['expires_ts'];
        if (expires is! int) return true;
        if (expires > now) return true;
      }
    }
    // Nothing of theirs for THIS call: either they never wrote one (we cannot
    // tell -- no opinion) or they retracted it (they left).
    return !sawAnyOfTheirs ? true : false;
  }

  /// Whether the call our [ownMembershipEventId] belongs to is still being
  /// held by somebody ELSE.
  ///
  /// What decides whether a standing "Return to call" offer still means
  /// anything. An offer is a promise that there is something to return to,
  /// and once the other person has gone the promise is false -- on a real
  /// phone that banner sat there long after the call was over, inviting the
  /// learner into an empty room.
  ///
  /// Reads the call id out of OUR own membership event, then asks whether any
  /// other user holds a live membership for that same call. Deliberately
  /// call-scoped and expiry-aware, for the reason [peerLiveInCurrentCall]
  /// states: a room accumulates a membership per device, and the broad read
  /// answers "yes" for ever.
  bool callStillHeldByAnother(Room room, String ownMembershipEventId) {
    final states = room.states[EventTypes.GroupCallMember];
    if (states == null) return false;
    final me = client.userID;
    String? callId;
    for (final state in states.values) {
      if (state is! Event) continue;
      if (state.eventId != ownMembershipEventId) continue;
      final memberships = state.content['memberships'];
      if (memberships is! List) continue;
      for (final m in memberships) {
        if (m is Map && m['call_id'] is String) callId = m['call_id'] as String;
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final state in states.values) {
      if (state is! Event) continue;
      if (state.senderId == me) continue;
      final memberships = state.content['memberships'];
      if (memberships is! List) continue;
      for (final m in memberships) {
        if (m is! Map) continue;
        // Call-scoped WHEN WE CAN: our own membership event names the call,
        // but the reload this offer exists for is exactly when the server may
        // already have emptied it -- and requiring it then withdrew the offer
        // the instant it appeared. Without a call id, "somebody else is still
        // on a call in this room" is the honest answer, and in a direct chat
        // there is only one call to be on.
        if (callId != null && m['call_id'] != callId) continue;
        final expires = m['expires_ts'];
        if (expires is! int || expires > now) return true;
      }
    }
    return false;
  }

  /// Leaves a call this device is no longer joined to.
  ///
  /// After a reload the session is gone but the membership it wrote is still
  /// standing, and the other person is watching their grace run down. Saying
  /// "no, I am not coming back" has to retract that membership, or they wait
  /// out the whole window for someone who already decided. Writes the state
  /// key the membership event itself carries, because that is the only way
  /// to name it without a session to ask.
  Future<bool> abandonCall(Room room, String ownMembershipEventId) async {
    final states = room.states[EventTypes.GroupCallMember];
    if (states == null) return false;
    for (final state in states.values) {
      if (state is! Event) continue;
      if (state.eventId != ownMembershipEventId) continue;
      final stateKey = state.stateKey;
      if (stateKey == null) return false;
      try {
        await client.setRoomStateWithKey(
          room.id,
          EventTypes.GroupCallMember,
          stateKey,
          {'memberships': <Map<String, Object?>>[]},
        );
        return true;
      } catch (e, s) {
        Logs().w('Could not leave the call we were offered back', e, s);
        return false;
      }
    }
    return false;
  }

  /// When the membership event [eventId] was written, if it is still in the
  /// room's state.
  ///
  /// What a rejoined session uses to keep the call's clock running. Rejoining
  /// started the timer at zero, so a learner who refreshed watched 0:00 while
  /// the other side read 4:12 -- the same call, two answers.
  DateTime? membershipWrittenAt(Room room, String eventId) {
    final states = room.states[EventTypes.GroupCallMember];
    if (states == null) return null;
    for (final state in states.values) {
      if (state is! Event) continue;
      if (state.eventId == eventId) return state.originServerTs;
    }
    return null;
  }

  /// Whether [eventId] is one of [userId]'s CURRENT membership state events.
  ///
  /// The discriminator between a STALE ring (replayed from before a reload,
  /// naming a membership that has since been rewritten or emptied) and a LIVE
  /// one. Asked this way round -- "is the ring's event still current" --
  /// because a sender can hold SEVERAL state keys (per-device and legacy
  /// shapes), and picking "the" current one would compare the ring against
  /// whichever the map yielded first; a live ring must match whichever entry
  /// is genuinely its own.
  bool membershipEventIsCurrent(Room room, String userId, String eventId) {
    final memberStates = room.states[EventTypes.GroupCallMember];
    if (memberStates == null) return false;
    for (final state in memberStates.values) {
      if (state is! Event) continue;
      if (state.senderId != userId) continue;
      if (state.eventId != eventId) continue;
      final memberships = state.content['memberships'];
      if (memberships is List && memberships.isNotEmpty) return true;
    }
    return false;
  }

  /// Whether ANOTHER device of this account has joined the call [ring] is
  /// for.
  ///
  /// A phone and a laptop both ring. Answering on one has to stop the other,
  /// and nothing said so: a decline is not sent when you ANSWER, so the
  /// second device went on offering a call that had already been picked up
  /// until its ring simply timed out. The evidence is our own membership
  /// appearing for that call from a device that is not this one -- no new
  /// message, and it cannot be faked by a stale row because it is scoped to
  /// the call the ring names and to memberships that have not expired.
  bool answeredOnAnotherDevice(Room room, DateTime ringSentAt) {
    final me = client.userID;
    final myDevice = client.deviceID;
    if (me == null || myDevice == null) return false;
    final states = room.states[EventTypes.GroupCallMember];
    if (states == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final state in states.values) {
      if (state is! Event) continue;
      if (state.senderId != me) continue;
      // WRITTEN AFTER THE RING. The call id cannot answer this question: it
      // is the ROOM id by design -- one direct message holds one live call --
      // so every call this room has ever had shares it, and every browser
      // login leaves another device's row behind. Matching on the id alone
      // read those old rows as "somebody answered" and dismissed incoming
      // rings the instant they arrived, which made calls unanswerable.
      // A membership written after the ring went out cannot be stale.
      if (!state.originServerTs.isAfter(ringSentAt)) continue;
      final memberships = state.content['memberships'];
      if (memberships is! List) continue;
      for (final m in memberships) {
        if (m is! Map) continue;
        if (m['device_id'] == myDevice) continue;
        final expires = m['expires_ts'];
        if (expires is! int || expires > now) return true;
      }
    }
    return false;
  }

  /// Fires whenever this account's OWN call membership in [room] changes --
  /// which is how a device learns that another of its siblings answered.
  Stream<void> ownPresenceChanges(Room room) => client.onRoomState.stream.where(
    (update) =>
        update.roomId == room.id &&
        update.state.type == EventTypes.GroupCallMember &&
        update.state.senderId == client.userID,
  );

  /// Fires whenever [callerId]'s call membership in [room] is rewritten.
  ///
  /// The signal a ringing device watches to notice the caller has given up.
  Stream<void> callerPresenceChanges(Room room, String callerId) =>
      client.onRoomState.stream.where(
        (update) =>
            update.roomId == room.id &&
            update.state.type == EventTypes.GroupCallMember &&
            update.state.senderId == callerId,
      );

  /// Rings that arrived while this device was not listening.
  ///
  /// [incomingRings] is a LIVE stream. A ring that landed before the page was
  /// reloaded never comes through it again — the learner could watch their
  /// phone ring, reload, and have no way left to answer. This reads them back
  /// out of the timeline that is already on disk.
  ///
  /// Bounded twice over: only direct rooms whose last event falls inside the
  /// longest lifetime a ring may have are opened at all, and the scan of each
  /// stops at the same cutoff. A ring is replayed only if it would still ring
  /// now, this account did not already turn it down, and the caller is still
  /// there — a ring whose caller has gone is a call that is already over.
  Future<List<IncomingCallNotification>> ringsMissed() async {
    final now = DateTime.now();
    final cutoff = now.subtract(CallNotification.maxLifetime);
    final missed = <IncomingCallNotification>[];
    for (final room in client.rooms) {
      if (!room.isDirectChat) continue;
      // Only a room that is KNOWN to be too old is skipped. A room whose last
      // event has not been worked out yet is still opened: treating unknown as
      // old would silently drop the call this whole method exists to recover.
      final last = room.lastEvent;
      if (last != null && last.originServerTs.isBefore(cutoff)) continue;
      // Call membership is state, and a room the learner has not opened is
      // loaded only partially. Without this the caller would read as absent —
      // and an absent caller is taken as a call already over, which would
      // silence exactly the ring being recovered.
      try {
        await room.postLoad();
      } catch (e, s) {
        Logs().w('Could not load the state of ${room.id}', e, s);
      }
      Timeline timeline;
      try {
        timeline = await room.getTimeline();
      } catch (e, s) {
        Logs().w('Could not reread ${room.id} for missed calls', e, s);
        continue;
      }
      try {
        // Both are gathered in one pass, newest first, because a decline is
        // only meaningful against a ring seen in the same window.
        final declined = <String>{};
        final rings = <IncomingCallNotification>[];
        for (final event in timeline.events) {
          if (event.originServerTs.isBefore(cutoff)) break;
          if (event.type == PangeaEventTypes.callDecline &&
              event.senderId == client.userID) {
            final target = _declineRefersTo(event);
            if (target != null) declined.add(target);
            continue;
          }
          if (event.type != PangeaEventTypes.callNotification) continue;
          rings.add(
            IncomingCallNotification(
              event: event,
              myUserId: client.userID ?? '',
              alreadyJoined: isBusy,
            ),
          );
        }
        for (final ring in rings) {
          if (!ring.shouldRing(now)) continue;
          if (declined.contains(ring.event.eventId)) continue;
          if (!callerStillInCall(room, ring.event.senderId)) continue;
          missed.add(ring);
        }
      } catch (e, s) {
        Logs().w('Could not read missed calls out of ${room.id}', e, s);
      } finally {
        timeline.cancelSubscriptions();
      }
    }
    return missed;
  }

  /// Calls this DEVICE was still on when it was last alive.
  ///
  /// A live, unexpired call membership of our own in a direct room is the
  /// trace a mid-call reload leaves behind. It is the OFFER heuristic only --
  /// membership is never liveness in this codebase, and its age says nothing
  /// about when the reload happened, because it is written at call START. The
  /// truth about whether the call still exists is the join itself: the rejoin
  /// waits briefly for the peer in the SFU roster and leaves quietly if the
  /// room is empty.
  /// The slack the SDK gives an expiry before believing it, so a device slow
  /// to renew is not read as gone. Mirrored here because this scan reads the
  /// raw state on purpose -- see below.
  static const _expiryBuffer = Duration(minutes: 1);

  Future<List<RejoinOffer>> rejoinOffers() async {
    if (_disposed) return const [];
    // The scan runs once, at startup -- exactly when the client is still
    // reading its room list out of the database after the reload this scan
    // exists for. Racing that load and losing returned an empty room list
    // and no offer, nondeterministically. Waiting is cheap and bounded: the
    // load is local.
    try {
      await client.roomsLoading;
    } catch (e, s) {
      Logs().w('Could not wait for the room list', e, s);
    }
    if (_disposed) return const [];

    // The breadcrumb FIRST. On a server with working delayed events, a dead
    // device's membership is retracted within seconds of its heartbeat
    // stopping -- racing, and often beating, this very scan. The breadcrumb
    // is the call's own local trace: written when it became a conversation,
    // erased only by its clean teardown, refresh-proof and answerable only
    // to its own age bound. Membership remains the fallback for a device
    // whose local storage did not survive.
    final crumb = await CallBreadcrumb.read();
    if (crumb != null) {
      final room = client.getRoomById(crumb.roomId);
      // Deliberately NOT re-checked as a direct chat: only a direct-chat call
      // ever writes the crumb, and m.direct lives in account data that may
      // not have loaded this early in the boot -- re-deriving the writer's
      // guarantee here made the offer vanish on exactly the starts it exists
      // for. The room merely has to exist.
      if (room != null) {
        return [
          RejoinOffer(
            room: room,
            membershipEventId: crumb.membershipEventId,
            since: crumb.at,
          ),
        ];
      }
    }
    final me = client.userID;
    final device = client.deviceID;
    if (me == null || device == null) return const [];
    final horizon = DateTime.now()
        .subtract(_expiryBuffer)
        .millisecondsSinceEpoch;
    final offers = <RejoinOffer>[];
    for (final room in client.rooms) {
      if (!room.isDirectChat) continue;
      // Membership is state, and a room the learner has not opened is loaded
      // only partially -- without this the membership this scan exists to find
      // reads as absent.
      try {
        await room.postLoad();
      } catch (e, s) {
        Logs().w('Could not load the state of ${room.id}', e, s);
      }
      // Raw state, NOT the SDK's membership helper: that helper needs VoIP,
      // and VoIP() is not inert -- it scans every joined room and can fire
      // call handlers on construction. This scan runs at every app start, and
      // an account that was not in a call must not pay that. Matched on the
      // state event's SENDER, like every other membership read here, because
      // the state key has three shapes and only the sender is common to all.
      final memberStates = room.states[EventTypes.GroupCallMember];
      if (memberStates == null) continue;
      for (final state in memberStates.values) {
        // Stripped state carries no event id, and the id IS the offer's value:
        // it is the call's standing identity, handed to the rejoined session.
        if (state is! Event) continue;
        if (state.senderId != me) continue;
        final memberships = state.content['memberships'];
        if (memberships is! List) continue;
        final mine = memberships.any((m) {
          if (m is! Map) return false;
          if (m['device_id'] != device) return false;
          final expires = m['expires_ts'];
          return expires is int && expires >= horizon;
        });
        if (!mine) continue;
        offers.add(RejoinOffer(room: room, membershipEventId: state.eventId));
        break;
      }
    }
    return offers;
  }

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

    // Never publish a membership while a leave that would retract it is still
    // in flight. The session is fetched by room, so a redial lands on the same
    // object a stalled leave still holds; if this enter wrote its membership and
    // that leave then finally landed, the leave would take the fresh call's
    // membership back — the peer would watch us walk out of a call we had only
    // just joined. Waiting here orders the two: the enter follows the leave.
    //
    // BOUNDED, though. `_leaving` can hold a raw session.leave() that never
    // answers — its own waiter in retract() only timed out, it did not stop the
    // call. Waiting on it without a limit would strand this new call in
    // connecting with its microphone already open (media.connect ran before
    // this) until something tore it down by hand, and the record's `settled`
    // would wait for ever too. So past the window the enter goes ahead: the rare
    // cost is that stale leave landing late and retracting this membership,
    // which is recoverable, where a call held open for ever is not.
    final pendingLeave = _leaving;
    if (pendingLeave != null) {
      _stopIfDisposed();
      Logs().i('Holding the membership until the last leave finishes');
      try {
        await pendingLeave.timeout(_leaveWithin);
      } catch (_) {
        // Settled, timed out, or failed — in every case the enter below may now
        // proceed. Its retract path owns any failure of the leave itself.
      }
      _stopIfDisposed();
    }

    // An enter already in flight is waited for, never doubled. The signal for
    // "in flight" is this future, not the session's state: with the LiveKit
    // backend enter() runs straight from an initialized state to `entered` and
    // never publishes an intermediate `entering`, so reading the state to spot
    // a running enter would spot nothing. Starting a second enter double-writes
    // the membership; going straight to the poll below let a slow-but-fine
    // enter miss the fixed membership window, so the call connected and never
    // rang. (Two announces racing one session needs two live calls on this
    // account, which the join guard refuses well before here — so this is the
    // honest invariant made safe rather than a reachable bug today.)
    final inFlight = _entering;
    if (inFlight != null) {
      await inFlight.timeout(_announceWithin);
    } else if (session.state != GroupCallState.entered) {
      // A leave that failed part-way can leave the SDK's session still entered,
      // and it is reused by the next join. Entering it again throws, which would
      // make every later call in that room fail for a transient error the
      // learner never saw. Already-entered is the state we wanted, and the check
      // above is what skips it.

      // Held so a retract cannot overtake it. Leaving while the enter write is
      // still in flight let that write land afterwards, advertising a
      // membership with nothing left tracking it — and this SDK's memberships
      // stand for minutes.
      final entering = _entering = session.enter();
      // Released when the enter itself finishes, NOT when this stops waiting
      // for it. Clearing it on the way out of a timeout let a retract go ahead
      // without waiting, and the leave could then be overtaken by an enter that
      // landed afterwards — advertising a membership with nothing left to take
      // it back, for the minutes it takes to expire.
      unawaited(
        entering
            .whenComplete(() {
              if (identical(_entering, entering)) _entering = null;
            })
            .onError((Object _, StackTrace _) {}),
      );
      // Bounded like every other network step in a call's life. Announcing is
      // awaited by the whole of coming up, and coming up is what the RECORD
      // waits on — so an enter that never answered meant the call was never
      // written and every word of it went uncredited, long after the learner
      // had closed the screen.
      await entering.timeout(_announceWithin);
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
          // Bounded. Everything after this frees the microphone and the camera,
          // and a leave that never came back held them open for as long as it
          // hung — in a call the learner had already left.
          //
          // Kept, not dropped: giving up waiting does not stop it. The session
          // is fetched by ROOM, so a redial lands on this same object, and a
          // leave that finally answered after that would retract the membership
          // the NEW call had just published — the peer would watch us walk out
          // of a call we had only just joined.
          final leaving = session.leave();
          _setPendingLeave(leaving);
          await leaving.timeout(_leaveWithin);
          _abandonedMembership = false;
          return true;
        } on TimeoutException catch (e, s) {
          // Not retried. The retries above are for a write that FAILED, which
          // the next one may well not; one that never answered will not answer
          // any faster on a second ask, and asking again doubles the time the
          // microphone stays open.
          Logs().w('Retracting the call membership did not answer', e, s);
          break;
        } catch (e, s) {
          // A leave is judged by the state it PRODUCED, not by whether every
          // step of the SDK's sequence returned success. leave() writes the
          // emptied membership first and only then does its own bookkeeping;
          // when a later step throws, the write has already landed and the peer
          // has already watched us go — but everything after the throw is
          // skipped, and that unfinished teardown is what breaks the NEXT call
          // in this room. Retrying cannot help: the write it would repeat is
          // the part that already worked.
          if (_myMembershipEventId(session.room) == null) {
            Logs().w('Leave threw after the membership was already gone', e, s);
            await _finishAbortedLeave(session);
            _abandonedMembership = false;
            return true;
          }
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

  /// Finishes a `leave()` that wrote the membership away and then threw.
  ///
  /// Everything here is what `GroupCallSession.leave()` does AFTER the write —
  /// release the media backend, forget the session, clear the current call. The
  /// SDK skips all of it when its post-write bookkeeping throws, and a session
  /// left in the registry is what makes the next call in this room fail as
  /// though we were still busy in this one.
  ///
  /// Each step is guarded on its own: this runs because something already went
  /// wrong, so one step failing must not stop the rest. Best effort by design —
  /// the membership, which is what the peer actually reads, is already gone.
  Future<void> _finishAbortedLeave(GroupCallSession session) async {
    try {
      await session.backend.dispose(session);
    } catch (e, s) {
      Logs().w(
        'Releasing the call backend after an aborted leave failed',
        e,
        s,
      );
    }
    try {
      session.setState(GroupCallState.ended);
    } catch (e, s) {
      Logs().w('Ending the call session after an aborted leave failed', e, s);
    }
    // By identity rather than by key: it drops exactly this session however the
    // registry happens to key it, and VoipId is not part of the SDK's exports.
    voip.groupCalls.removeWhere((_, entry) => identical(entry, session));
    if (voip.currentGroupCID?.roomId == session.room.id) {
      voip.currentGroupCID = null;
    }
  }

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

  /// Installs a joined session without going through the network join, so a
  /// test can exercise what retract does with one.
  @visibleForTesting
  void adoptSessionForTest(GroupCallSession session) => _current = session;

  @visibleForTesting
  bool get voipConstructed => _voip != null;
}

/// Raised when this account is already in a call, or already joining one.
///
/// A distinct type because the caller has to tell it apart from a join that
/// failed: one that was refused never held the account's claim, and giving that
/// claim up on the way out would cancel somebody else's join.
class AlreadyInACall implements Exception {
  const AlreadyInACall();

  @override
  String toString() => 'This account is already in a call';
}

/// A call this device can offer to return to after a reload.
class RejoinOffer {
  final Room room;

  /// This device's own live membership event: the call's standing identity,
  /// carried into the rejoined session as its anchor rather than minting a
  /// new one for a call that already has one.
  final String membershipEventId;

  /// When this device was IN the call, from its breadcrumb. Null for offers
  /// recovered from the membership fallback. The arbitration line for rings
  /// in the same room: one sent BEFORE this moment belongs to the very call
  /// being offered back -- it rang, we answered, we died -- while one sent
  /// after is a genuine new call, which wins.
  final DateTime? since;

  const RejoinOffer({
    required this.room,
    required this.membershipEventId,
    this.since,
  });
}
