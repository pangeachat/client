import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_breadcrumb.dart';
import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/call_timeouts.dart';
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

  /// The room this account's one call claim is FOR.
  ///
  /// Busy means "in a call with somebody else". A ring from the room we are
  /// already calling is not somebody else -- it is the same conversation,
  /// arriving as glare when both people press call at the same moment -- and
  /// auto-declining it as busy hung up a call that was coming up perfectly
  /// well. Kept alongside the claim rather than derived, because it has to be
  /// answerable while the join is still in flight.
  String? _claimedRoomId;

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
    CallTimeouts? timeouts,
  }) : delegate = delegate ?? PangeaVoipDelegate(),
       timeouts = timeouts ?? pangeaCallTimeouts(),
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
  ///
  /// [timeouts] is passed rather than left to the SDK's defaults. Those put a
  /// delayed-leave restart on the wire every four seconds per participant, and
  /// every device on the same period; see [CallDelayedLeave] for what replaces
  /// them and why the two numbers had to move together.
  VoIP get voip => _voip ??= VoIP(client, delegate, timeouts: timeouts);

  /// The delayed-leave timings this account's calls run with, drawn once.
  ///
  /// Held here rather than built inside [voip] so the draw is stable across the
  /// account's calls and so a test can read what was actually passed.
  final CallTimeouts timeouts;

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
    _claimedRoomId = room.id;
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

  /// EVERY leave that was given up on and is still running. The next call in
  /// this room waits for all of them rather than racing any.
  ///
  /// A SET, not a slot, and the difference is the whole of what this holds. A
  /// slot records the LATEST leave, which silently UNRECORDS the one before it
  /// — and a leave dropped from the tracker is exactly as invisible to
  /// [settlePendingLeave] and to the wait in [announce] as one that was never
  /// funnelled through [_leave] at all. Two can be outstanding at once by the
  /// ordinary route: [retract] gives up waiting on its leave without stopping
  /// it, the redial that follows is abandoned mid-join, and the leave that
  /// abandonment issues for the session it was holding is a second one. On a
  /// slot the second finishes, clears it, and the first is left in flight with
  /// nothing waiting for it — so the call after that publishes its membership
  /// into the session both of them hold, and the first lands late and retracts
  /// a LIVE call's membership. That is the exact failure the funnel exists to
  /// prevent, moved one level down into what the funnel writes to.
  final Set<Future<void>> _leaving = {};

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
    _leaving.add(leaving);
    unawaited(
      leaving
          .whenComplete(() => _leaving.remove(leaving))
          .catchError((Object _, StackTrace _) {}),
    );
  }

  /// Every leave still outstanding, as one future to wait on, or null when
  /// there are none.
  ///
  /// A SNAPSHOT of the set, so a leave issued while somebody is already waiting
  /// does not extend that wait. Which is right for both kinds of leave that can
  /// appear inside one, and for opposite reasons: a leave belonging to a LATER
  /// call takes its own snapshot when its turn comes, while a leave belonging to
  /// the very call that is waiting — this call's own hangup — is not something
  /// to wait for at all, since waiting for it would be waiting for a session to
  /// be left in order to enter it.
  ///
  /// So a waiter cannot decide anything by re-reading this: a `Future<void>`
  /// does not say whose leave it is. [announce] asks the service's own state
  /// instead — see [announceStillHolds].
  ///
  /// A RETRACT IN FLIGHT COUNTS, EVEN WHEN IT IS HOLDING NO LEAVE AT THIS
  /// INSTANT. What a redial has to be ordered behind is every leave this
  /// service is STILL GOING TO ISSUE, not merely the ones already on the wire.
  /// [_leaving] holds a leave only while its future is outstanding, and it
  /// forgets one that FAILED just as readily as one that worked — so between
  /// the retract's retries, while it sleeps for a second and then two, there is
  /// a retract that will issue another leave and nothing in [_leaving] to see
  /// it by. In that window [settlePendingLeave] found nothing to wait for and
  /// [announce] skipped its whole guard, [announceStillHolds] included, because
  /// that guard is nested inside "is there a pending leave". The redial
  /// published its membership into the session — fetched by ROOM, so the very
  /// object the sleeping retract still holds — and the retract woke and took
  /// the LIVE call's membership straight back off it.
  Future<void>? get _pendingLeaves {
    final outstanding = <Future<void>>[..._leaving, ?_retracting];
    return outstanding.isEmpty ? null : Future.wait(outstanding);
  }

  /// Issues a leave and records it among the pending ones, in that order and
  /// with nothing awaited in between.
  ///
  /// EVERY LEAVE THIS SERVICE ISSUES MUST BE ONE THE NEXT JOIN CAN WAIT FOR.
  /// [settlePendingLeave] and the wait in [announce] are the whole machinery for
  /// ordering a redial behind a leave that has not finished, and both of them
  /// read [_leaving] — so a leave that was never recorded there is not merely
  /// unwaited-for, it is invisible to the thing built to serialise leaves. The
  /// session is fetched by ROOM, so the redial is handed the very object the
  /// unrecorded leave still holds: it sees nothing to wait for, publishes its
  /// membership into that session, and the older leave lands afterwards and
  /// takes the LIVE call's membership back. That is worse than the abandoned
  /// membership the leave was cleaning up, which expires by itself in minutes,
  /// where a conversation dropped mid-sentence does not come back.
  ///
  /// A funnel rather than a rule to remember at each site, because remembering
  /// is exactly what failed: [retract] recorded its leave and the abandoned-join
  /// path did not, and nothing at either site said which of the two it was. With
  /// one way to leave there is no second site to keep in step.
  Future<void> _leave(GroupCallSession session) {
    final leaving = session.leave();
    _setPendingLeave(leaving);
    return leaving;
  }

  /// Waits for every leave that was given up on to actually finish.
  ///
  /// Bounded: waiting longer would hold up a call the learner is asking for now,
  /// so after the window the call goes ahead. But the pending leaves are NOT let
  /// go of here — each clears itself when it completes — so every call that
  /// starts while any is still running waits for it in turn rather than racing
  /// it. That is the whole protection against a stale leave retracting a fresh
  /// call's membership; dropping it on the first timeout threw that protection
  /// away for every call after.
  @visibleForTesting
  Future<void> settlePendingLeave() async {
    final leaving = _pendingLeaves;
    if (leaving == null) return;
    Logs().i('Waiting for every leave still running to finish');
    try {
      await leaving.timeout(_leaveWithin);
    } catch (_) {
      // Waited as long as is reasonable; the leaves keep running and are
      // forgotten only when they finish, not here.
    }
  }

  /// Puts a still-running leave in place, for tests.
  @visibleForTesting
  void setPendingLeaveForTest(Future<void> leaving) =>
      _setPendingLeave(leaving);

  /// Whether any leave is still being waited for. For tests.
  @visibleForTesting
  bool get hasPendingLeaveForTest => _leaving.isNotEmpty;

  /// How many leaves are still outstanding. For tests: the count is what tells
  /// a tracker that KEEPS both from one that has quietly replaced the first.
  @visibleForTesting
  int get pendingLeaveCountForTest => _leaving.length;

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

  /// Stops a join the account no longer wants, handing back anything it had
  /// already taken.
  ///
  /// AN AWAIT IS A PLACE A DECISION CAN BE SUPERSEDED, AND NOTHING AFTER ONE MAY
  /// ACT ON THE DECISION THAT PRECEDED IT. Coming up is three network
  /// round-trips, and both a hangup ([abandonJoin]) and a logout can land inside
  /// any of them — so what this account wanted when a step was issued says
  /// nothing about what it wants when that step answers. Called after EVERY
  /// await in [_join] rather than once at the end, because the end is not
  /// reached on the paths that matter: the check used to sit below the token
  /// request, so a token that threw carried the failure out past it and the
  /// session fetched a moment earlier was never handed back — a membership left
  /// advertised for the minutes it takes to expire.
  ///
  /// The same shape as `_decisionHolds` and `_step` in `ActiveCall`, and as the
  /// session gate in `CallCaptureService.start`.
  ///
  /// [session] is whatever this join is holding by the time it gets here, and
  /// null before it holds anything. Handed back on exactly the terms
  /// [releasesAbandonedSession] states, and BEFORE either throw below, so the
  /// release is not something a caller has to remember to do on the way out.
  Future<void> _stopIfSuperseded(
    int attempt, {
    GroupCallSession? session,
  }) async {
    if (!_disposed && attempt == _joinAttempt) return;
    // The account went away while this join was in flight, or the join itself
    // was given up on. Storing the session now would advertise a membership
    // that nothing is left to retract, and it would stand until it expired
    // minutes later.
    if (session != null &&
        releasesAbandonedSession(
          joinInFlight: _joining,
          isCurrent: identical(session, _current),
        )) {
      try {
        // Through [_leave], never straight at the session. This leave runs in
        // the one window where nothing else is holding the room — the join that
        // owned it has been given up on and the redial has not claimed it yet —
        // so it is precisely the leave a redial has to be able to wait for.
        await _leave(session);
      } catch (e, st) {
        Logs().w('Could not leave a call abandoned during teardown', e, st);
      }
    }
    // Disposal keeps saying so in its own words: it is the one of the two that
    // means the whole service is gone rather than this one call, and the
    // distinction is what a reader of the log needs.
    _stopIfDisposed();
    throw StateError('the call was abandoned while joining');
  }

  /// The two network steps of joining, named so the sequence and the checks
  /// between them can be observed. Neither can be stood up in a unit test — one
  /// needs a live SFU and the other the choreographer — and the ordering is the
  /// part worth testing.
  ///
  /// Room-scoped call id: one direct message room holds at most one live call,
  /// and both clients derive the same id without coordinating.
  @protected
  Future<GroupCallSession> fetchSession(
    Room room,
    RtcFocus focus,
  ) => voip.fetchOrCreateGroupCall(
    room.id,
    room,
    focus.backendForRoom(room.id),
    'm.call',
    'm.room',
    // Defaults to true, which pre-generates and broadcasts an E2EE key before the
    // call even starts. With e2eeEnabled false the SDK returns early from that work
    // anyway, so this changes no behaviour — it just stops us asking for key
    // distribution we have deliberately turned off.
    preShareKey: false,
  );

  @protected
  Future<CallToken> requestToken(Room room, RtcFocus focus) =>
      _tokens.requestToken(
        client: client,
        roomId: room.id,
        focusServiceUrl: focus.serviceUrl,
      );

  Future<CallToken> _join(Room room, int attempt) async {
    // A leave still finishing was waited for before this ran, and a hangup can
    // land inside that wait like any other.
    await _stopIfSuperseded(attempt);
    final f = await resolveFocus();
    // Before anything is constructed: discovery is a network round-trip, and
    // both the account and the user's mind can change inside it.
    await _stopIfSuperseded(attempt);
    if (f == null) {
      throw StateError('this homeserver advertises no MatrixRTC focus');
    }

    final session = await fetchSession(room, f);
    // BEFORE the token is asked for, not after. A join nobody wants any more
    // must not spend a choreographer request on itself, and — the reason this
    // moved — the session it is holding has to be handed back on a path that
    // does not depend on that request ever answering.
    await _stopIfSuperseded(attempt, session: session);

    final CallToken grant;
    try {
      grant = await requestToken(room, f);
    } catch (_) {
      // A token failure is the caller's to hear, but a join abandoned while it
      // was in flight still owns a session, and the throw would carry straight
      // past the check below and leave it advertised. Asked here so the release
      // happens on the failing path too; when nothing superseded this join the
      // guard returns and the original failure goes on out.
      await _stopIfSuperseded(attempt, session: session);
      rethrow;
    }
    await _stopIfSuperseded(attempt, session: session);

    _markCallBegun(session);
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

  /// The membership event id that IDENTIFIES the call in hand, or null.
  ///
  /// Read again at the end of a call by a device that had none: the wait when
  /// announcing is deliberately short so a caller is never left hanging, and a
  /// device that joined a call already under way has nothing else to anchor its
  /// analytics to.
  ///
  /// A CALL'S ANCHOR MUST BE A MEMBERSHIP THAT CALL ITSELF PUBLISHED. Every
  /// writer keys on it — the transcript's transaction id is built from it, and
  /// so is the card — and both of those jobs assume it is unique per call. It
  /// is unique only because each publish takes a fresh event id; two calls that
  /// derive the SAME one are two calls of which only the FIRST is ever written,
  /// because a homeserver collapses a repeated transaction id from one device
  /// and hands back the earlier event. Nothing fails: the later call's whole
  /// transcript is absorbed as a duplicate of a call that had already ended,
  /// and its card is drawn with that call's duration.
  ///
  /// Room state on its own cannot say which membership belongs to which call —
  /// see [_membershipsStandingBefore].
  String? membershipEventIdIn(Room room) {
    // Answered only while the machinery that tracked the call is still here.
    // Reading a membership goes through the SDK's VoIP instance, and asking
    // after teardown would BUILD one — listeners and all — to answer a question
    // about a call that no longer exists.
    if (_disposed || _voip == null || _current == null) return null;
    return _thisCallsMembershipEventId(room);
  }

  /// Every membership of ours the room is holding for the call in hand.
  ///
  /// Expiry is the only thing state itself can rule out, and it rules out very
  /// little: a membership stands for minutes after the call it belonged to has
  /// ended.
  List<CallMembership> _myMembershipsIn(Room room) {
    // An account with no user or device id of its own holds no memberships,
    // which is the honest answer rather than a crash. The bangs this replaces
    // were never load-bearing: nothing about a logged-out client makes it own
    // a membership, so there is no case where throwing said more than this.
    final userId = client.userID;
    final deviceId = client.deviceID;
    if (userId == null || deviceId == null) return const [];
    return [
      for (final m in room.getCallMembershipsForUser(userId, deviceId, voip))
        if (m.callId == _current?.groupCallId && !m.isExpired) m,
    ];
  }

  /// Any membership of ours still standing, a leftover of an earlier call
  /// included.
  ///
  /// The question a RETRACT asks on its way out — is there anything of ours
  /// left in this room to take back? — where a leftover counts like any other,
  /// which is why this one is deliberately not filtered.
  String? _myMembershipEventId(Room room) {
    final mine = _myMembershipsIn(room);
    return mine.isEmpty ? null : mine.first.eventId;
  }

  /// The membership THIS call published, never one it merely found.
  ///
  /// Identified by what the publish STAMPED ON IT, which is the only thing in
  /// the room that speaks for the write rather than for the moment it was
  /// read. Anything weaker is a guess: see [_anchorStampFloor].
  String? _thisCallsMembershipEventId(Room room) {
    final floor = _anchorStampFloor;
    if (floor == null) return null;
    for (final m in _myMembershipsIn(room)) {
      if (m.eventId != null && m.expiresTs >= floor) return m.eventId;
    }
    return null;
  }

  /// The earliest `expires_ts` a membership can carry and still be one THIS
  /// call published. Null until this call has asked to publish one, which is
  /// the honest answer then: it has no identity yet.
  ///
  /// THE ROOM CANNOT BE ASKED WHICH CALL A MEMBERSHIP BELONGS TO. The group
  /// call id IS the room id (one direct message holds at most one call, and
  /// both clients derive the same id without coordinating), so every membership
  /// of ours in this room matches the current call. There is ONE membership
  /// state event per account and device, so every write replaces the last and
  /// takes a fresh event id, and local state learns of it only when its echo
  /// comes back down /sync.
  ///
  /// SO THE EVENT ID SAYS NOTHING ON ITS OWN, AND NEITHER DOES WHEN IT ARRIVED.
  /// The call before this one can still have a write in flight when this one
  /// begins — its refresh, issued before the hangup cancelled the timer — and
  /// that write echoes back afterwards under an id this call has never seen.
  /// Deciding by "was it here when I started" adopts it, and this call's
  /// transcript and card are then keyed to the call before it: the collision
  /// this whole read exists to refuse, reached by a later road.
  ///
  /// What does speak for the write is the stamp the write puts on itself. The
  /// SDK publishes every membership with `expires_ts` set to this DEVICE's
  /// clock plus [CallTimeouts.expireTsBumpDuration] — the same bump this
  /// service configured the SDK with — so the stamp says when the write was
  /// ISSUED. A write issued before this call asked to publish carries an
  /// earlier stamp however late it lands, and no arrival can disguise it.
  ///
  /// The stamp is a millisecond, so two writes inside one millisecond are
  /// indistinguishable here and the earlier one would be accepted. That is the
  /// limit of the resolution the protocol gives, and it is not a window
  /// anything reaches: between the previous call's last write and this one's
  /// enter sit a leave, a join and their round trips.
  ///
  /// ONE CLOCK, DELIBERATELY. Floor and stamp are both this device's, so
  /// nothing here compares a local clock against the server's — the mistake
  /// [ActiveCall] already records having made about a call's own start time.
  /// A clock that steps backwards makes this refuse OUR OWN membership, which
  /// is a stated failure (below), never a wrong key.
  ///
  /// The same rule [peerPresenceInCurrentCall] applies to the PEER's
  /// memberships ("state older than this call cannot speak for it"), applied at
  /// last to our own — where it matters more, because our own membership is
  /// not merely read, it is PUBLISHED as the call's identity.
  ///
  /// A rejoin is not an exception. It announces itself afresh rather than
  /// reusing the standing membership — that is what re-enters the RTC session
  /// and renews the delayed leave — and the identity of the call it returned
  /// to is carried separately, as `ActiveCall._rejoinAnchorId`.
  int? _anchorStampFloor;

  /// The stamp a membership published at [issuedAt] carries.
  int _membershipStampFor(DateTime issuedAt) =>
      issuedAt.add(timeouts.expireTsBumpDuration).millisecondsSinceEpoch;

  /// A call becomes the current one. It has published nothing yet, so it has
  /// no membership of its own to be found and no anchor to answer with.
  void _markCallBegun(GroupCallSession session) {
    _current = session;
    _anchorStampFloor = null;
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
            couldRingHere(event.room),
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
          // Not for the room we are already calling: that ring is the other
          // half of a simultaneous call, and the glare tie-break decides it.
          ring.event.room.id != _claimedRoomId &&
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
  ///
  /// Answered against the DEVICE that placed the ring when the ring says which
  /// one, because "does this user hold a membership anywhere in this room" is
  /// not the question. A caller with a second device that CRASHED in an
  /// earlier call leaves a non-empty membership standing for minutes, and it
  /// kept the prompt ringing after the calling device had retracted -- so the
  /// callee could answer a call that had already been cancelled. Falls back to
  /// the user-wide read when the ring names no device, which is the behaviour
  /// this had before.
  bool callerStillInCall(Room room, String callerId, {String? deviceId}) =>
      callerPresence(room, callerId, deviceId: deviceId) == PeerPresence.live;

  /// The same question with the third answer kept.
  ///
  /// The boolean above is right where a MISSING caller should simply leave
  /// things as they are -- the ring watcher only acts on a transition it has
  /// seen. Anywhere a decision turns on the caller NOT being there, use this:
  /// room state lags a join by seconds, and "their state has not arrived yet"
  /// is not "they are not calling".
  PeerPresence callerPresence(Room room, String callerId, {String? deviceId}) {
    final memberStates = room.states[EventTypes.GroupCallMember];
    if (memberStates == null || memberStates.isEmpty) {
      return PeerPresence.unknown;
    }
    var sawTheirs = false;
    for (final state in memberStates.values) {
      if (state.senderId != callerId) continue;
      final memberships = state.content['memberships'];
      if (memberships is! List) continue;
      // An EMPTY list carries no device id -- there is no membership left to
      // hold one -- so it is attributed by its STATE KEY. A key naming a
      // device speaks for that device alone: the caller's laptop retracting
      // when it ended an earlier call says nothing about the phone that is
      // ringing now, and reading it as "that phone is gone" dropped the
      // recovered ring and rang the caller out. Only the legacy key that is
      // the bare user id, which no device can be read out of, speaks for the
      // whole user.
      final speaksForEveryDevice =
          memberships.isEmpty && state.stateKey == callerId;
      if (!speaksForEveryDevice &&
          deviceId != null &&
          !_belongsToDevice(state, memberships, deviceId)) {
        continue;
      }
      sawTheirs = true;
      if (memberships.isNotEmpty) return PeerPresence.live;
    }
    // They wrote state and it holds nothing: they have gone. Nothing of
    // theirs at all: we simply cannot see yet.
    return sawTheirs ? PeerPresence.gone : PeerPresence.unknown;
  }

  /// Whether a member state event is the work of one particular device.
  ///
  /// The membership's own `device_id` first; the state key only as a fallback,
  /// because the key has three shapes across MSC3757 and the per-device
  /// variants and matching it is guesswork where the field is not.
  bool _belongsToDevice(
    StrippedStateEvent state,
    List<Object?> memberships,
    String deviceId,
  ) {
    var sawDeviceField = false;
    for (final m in memberships) {
      if (m is! Map) continue;
      final id = m['device_id'];
      if (id is String) {
        sawDeviceField = true;
        if (id == deviceId) return true;
      }
    }
    if (sawDeviceField) return false;
    return state.stateKey?.contains(deviceId) ?? false;
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

  /// Whether a ring in this room could be a 1:1 call for us.
  ///
  /// `isDirectChat` reads `m.direct` account data, which at cold start -- the
  /// app woken by a call, or reloaded while one is ringing -- has not
  /// necessarily loaded yet. Treating "not known to be a DM" as "not a DM"
  /// dropped real calls at exactly the moment they matter, and the live ring
  /// stream never redelivers. A room with two people in it is a direct call
  /// whatever the account data has managed to say so far, and the member
  /// count comes from the room summary, which is there from the first sync.
  static bool couldRingHere(Room room) =>
      room.isDirectChat || room.summary.mJoinedMemberCount == 2;

  /// Kept for callers that only need "assume present unless proven otherwise".
  /// Anything that acts on a DEPARTURE should read
  /// [peerPresenceInCurrentCall] instead, because it can tell a retraction
  /// from a silence and those two mean opposite things.
  bool peerLiveInCurrentCall(Room room, String peerId, {DateTime? notBefore}) =>
      peerPresenceInCurrentCall(room, peerId, notBefore: notBefore) !=
      PeerPresence.gone;

  /// What the room's state says about [peerId] being in the call we are on.
  ///
  /// Three answers, not two, because "they retracted" and "they have not said
  /// anything yet" are opposites and the boolean above collapses them. Reading
  /// a retraction as silence is what made a deliberate hangup look like a
  /// crash; reading silence as a retraction would end calls that had only just
  /// begun, since state lags a join by seconds.
  PeerPresence peerPresenceInCurrentCall(
    Room room,
    String peerId, {
    DateTime? notBefore,
    DateTime? goneAfter,
  }) {
    final callId = _current?.groupCallId ?? _callIdForTest;
    if (callId == null) return PeerPresence.unknown;
    final states = room.states[EventTypes.GroupCallMember];
    if (states == null) return PeerPresence.unknown;
    final now = DateTime.now().millisecondsSinceEpoch;
    var sawTheirState = false;
    for (final state in states.values) {
      if (state.senderId != peerId) continue;
      final memberships = state.content['memberships'];
      if (memberships is! List) continue;
      // State older than this call cannot speak for it. The call id is the
      // room id, so a membership another of their devices left standing when
      // it CRASHED in an earlier call looks exactly like a live one here, and
      // it outvoted the retraction their current device had just written --
      // the hangup read as a vanish again, one layer further down. Nothing in
      // this call can have been written before [notBefore], so anything that
      // was belongs to a call that is over.
      if (notBefore != null &&
          state is Event &&
          state.originServerTs.isBefore(notBefore)) {
        continue;
      }
      // A list they actually WROTE is an answer, including an empty one.
      // Hanging up rewrites this event to `memberships: []`, so treating the
      // empty list as "no opinion" read a deliberate departure as a vanish
      // and made the other side sit through a 20-second grace for someone who
      // had already gone. No opinion means never having seen them write one.
      //
      // PRESENCE is read first, and from every event that passed the
      // staleness floor. The caller joined before we answered, so their live
      // membership is older than our join -- gating the whole event on the
      // departure floor below skipped it, presence fell to "cannot see", and
      // the remembered sighting turned that into "gone". Calls died two
      // seconds after being answered.
      for (final m in memberships) {
        if (m is! Map) continue;
        if (m['call_id'] != callId) continue;
        final expires = m['expires_ts'];
        if (expires is! int) return PeerPresence.live;
        if (expires > now) return PeerPresence.live;
      }
      // Only a departure written since WE joined can be a departure from THIS
      // call. Presence may predate our join; a retraction cannot, because it
      // ends the call that was live when it was written. Counting an older one
      // meant a redial moments after hanging up read the PREVIOUS call's
      // retraction as this call's.
      if (goneAfter != null &&
          state is Event &&
          state.originServerTs.isBefore(goneAfter)) {
        continue;
      }
      sawTheirState = true;
    }
    // Nothing live of theirs for THIS call. If they wrote state at all, that
    // is them gone; if they never did, we genuinely cannot tell.
    return sawTheirState ? PeerPresence.gone : PeerPresence.unknown;
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
  /// Kept for callers that only need "assume the call is still there unless
  /// proven otherwise". Anything that WITHDRAWS an offer must read
  /// [callHoldByAnother] instead, for the reason stated there.
  bool callStillHeldByAnother(
    Room room,
    String ownMembershipEventId, {
    DateTime? notBefore,
  }) =>
      callHoldByAnother(room, ownMembershipEventId, notBefore: notBefore) !=
      CallHold.over;

  /// The earliest a membership can have been written and still belong to the
  /// call this device joined at [ourJoin].
  ///
  /// One ring lifetime earlier, because the person who CALLED us was already
  /// in the call while our phone was ringing -- their membership is older than
  /// our answer by however long we took to pick up, and a floor set at our own
  /// join throws it away. That is not hypothetical: it read the caller, who
  /// was sitting in the call waiting, as nobody, and withdrew the Return offer
  /// the moment it appeared. A ring cannot outlive its lifetime, so nothing
  /// older than that can belong to the call it invited us to.
  static DateTime? callFloorFrom(DateTime? ourJoin) =>
      ourJoin?.subtract(CallNotification.lifetime);

  /// Whether anybody ELSE is still holding the call our membership belongs to.
  ///
  /// Three answers, for the third time in this file and for the same reason:
  /// "nobody is holding it" and "we cannot see any call state yet" are
  /// opposites, and a boolean makes them the same. This read runs at STARTUP,
  /// against a client that is still filling in room state, and a withdrawal
  /// on the second answer takes down the offer -- and the breadcrumb behind
  /// it -- for a call that is alive and waiting.
  CallHold callHoldByAnother(
    Room room,
    String ownMembershipEventId, {
    DateTime? notBefore,
  }) {
    final states = room.states[EventTypes.GroupCallMember];
    if (states == null || states.isEmpty) return CallHold.unknown;
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
      // Nothing written before this call began can prove it is still being
      // held. The reload this offer exists for is exactly when our own event
      // has been emptied, so the call-scoped filter below goes quiet -- and
      // with the call id being the room id, another device's membership left
      // standing by a crash in an EARLIER call then read as somebody still on
      // this one, and the Return offer invited the learner into an empty room
      // until that stale membership expired.
      if (notBefore != null && state.originServerTs.isBefore(notBefore)) {
        continue;
      }
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
        if (expires is! int || expires > now) return CallHold.held;
      }
    }
    // Somebody else's state is here and none of it holds this call. That is
    // an answer; an empty room state map, above, is not.
    return CallHold.over;
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
    // The same wait the rejoin scan makes, for the same reason and the same
    // race: this runs once at startup, which is exactly when the client is
    // still reading its room list out of the database after the reload this
    // scan exists for. Losing that race means iterating NO rooms and finding
    // no ring -- so a learner who reloads while their phone is ringing is
    // never offered the call again, and the caller rings out. Silent, because
    // an empty room list is indistinguishable from nobody calling.
    try {
      await client.roomsLoading;
    } catch (e, s) {
      Logs().w('Could not wait for the room list', e, s);
    }
    final now = DateTime.now();
    final cutoff = now.subtract(CallNotification.maxLifetime);
    final missed = <IncomingCallNotification>[];
    for (final room in client.rooms) {
      if (!couldRingHere(room)) continue;
      // Only a room that is KNOWN to be too old is skipped. A room whose last
      // event has not been worked out yet is still opened: treating unknown as
      // old would silently drop the call this whole method exists to recover.
      // No cheap freshness pre-filter here, and there cannot be one built on
      // `lastEvent`: that getter only reports the event types a room LIST can
      // display, and a call notification is not one of them. So in the very
      // rooms this scan exists for -- where a ring is the newest thing that
      // happened -- `lastEvent` reports the last ordinary message instead,
      // which in a room people mostly CALL in can be hours old. The filter
      // then skipped exactly the room holding the ring, and a learner who
      // reloaded while their phone was ringing was never offered the call
      // again. A pre-filter that cannot see the thing being searched for is
      // not an optimisation, it is a silent miss.
      //
      // The cost is one timeline load per direct chat at startup, bounded by
      // how many direct chats the learner has. If that ever matters, the
      // answer is a filter the SERVER applies, not a blind local guess.
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
          // Against the DEVICE that rang, for the reason the live watcher
          // uses it: another of their devices with a stale membership would
          // otherwise revive a ring its owner had already cancelled.
          //
          // Suppressed only on the answer that says they are GONE. This scan
          // runs at cold start, when room state is exactly what has not
          // loaded yet, and collapsing "cannot see" into "not there" dropped
          // live incoming calls: the caller rang on, the callee saw nothing,
          // and it was written down as a missed call. The ring's own lifetime
          // is the safety bound on being wrong the other way.
          if (callerPresence(
                room,
                ring.event.senderId,
                deviceId: ring.senderDeviceId,
              ) ==
              PeerPresence.gone) {
            continue;
          }
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
    final crumb = await CallBreadcrumb.read(client.clientName);
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
            video: crumb.video,
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
      if (!couldRingHere(room)) continue;
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
    final pendingLeave = _pendingLeaves;
    if (pendingLeave != null) {
      _stopIfDisposed();
      Logs().i('Holding the membership until every pending leave finishes');
      try {
        await pendingLeave.timeout(_leaveWithin);
      } catch (_) {
        // Settled, timed out, or failed — in every case the enter below may now
        // proceed. Its retract path owns any failure of the leave itself.
      }
      _stopIfDisposed();
      // AN AWAIT IS A PLACE A DECISION CAN BE SUPERSEDED. The session was read
      // before that wait, and the wait is bounded by seconds — long enough for
      // a hangup to run a whole retract inside it. Entering afterwards would
      // publish a membership on a call the service is no longer tracking, and
      // the next retract would find nothing to leave and report a success it
      // had not achieved: the peer keeps seeing us in a call we have left,
      // until it expires minutes later.
      //
      // What is re-established is not just WHICH session this is but whether it
      // is still WANTED; see [announceStillHolds] for why identity alone says
      // less than it looks like it says.
      if (!announceStillHolds(
        isCurrent: identical(_current, session),
        retractInFlight: _retracting != null,
        membershipAbandoned: _abandonedMembership,
      )) {
        Logs().i('The call ended while its membership was waiting to be sent');
        return null;
      }
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

      // Taken BEFORE the write, so it is a true lower bound on what the write
      // stamps itself with: the SDK reads its own `DateTime.now()` inside.
      // This is the moment this call acquires an identity at all — every read
      // before it honestly has none.
      _anchorStampFloor = _membershipStampFor(DateTime.now());
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

  /// Whether the call [announce] read before waiting is still one this service
  /// wants a membership published for.
  ///
  /// Identity is necessary and NOT sufficient, because [_current] outlives the
  /// decision to leave: [retract] captures the session, issues the leave, and
  /// clears [_current] only in a `finally` once that leave has finished — and
  /// when the leave was given up on it does not clear it at all, which is what
  /// leaves a later retry something to retry WITH. So for the whole time this
  /// call's own hangup is leaving the session, and afterwards if that hangup
  /// failed, an identity check sees the session it read and says yes.
  ///
  /// Entering there puts an `enter()` beside a `leave()` for the SAME session,
  /// and whichever lands last decides what the peer sees: a membership
  /// resurrected after a hangup the learner watched succeed, or a fresh
  /// membership taken straight back off them.
  ///
  /// The other way a session stops being current — a join abandoned in
  /// [_stopIfSuperseded] — is covered by identity alone: that path leaves a
  /// session only when it is NOT the current one (see
  /// [releasesAbandonedSession]), so it never leaves the one an announce holds.
  ///
  /// [membershipAbandoned] cannot be a leftover from an earlier call: [join]
  /// discards an abandoned membership, with the session it belongs to, before
  /// any new call can be made.
  @visibleForTesting
  static bool announceStillHolds({
    required bool isCurrent,
    required bool retractInFlight,
    required bool membershipAbandoned,
  }) => isCurrent && !retractInFlight && !membershipAbandoned;

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
      // The filtered read: what is being waited for is the echo of the write
      // `enter()` just made, and a membership already in state is by definition
      // not that.
      final id = _thisCallsMembershipEventId(room);
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
  ///
  /// A MEMOIZED IN-FLIGHT FUTURE IS CLEARED BY THE CODE THAT ASSIGNS IT, NEVER
  /// FROM INSIDE THE BODY IT MEMOIZES. An async body runs synchronously until
  /// its first await, and this one has a path that returns without ever
  /// awaiting -- there is nothing to retract. On that path the body, its
  /// `finally` included, finishes BEFORE `??=` has assigned anything: the clear
  /// ran against a latch that was still null, and the finished future was
  /// latched afterwards with nothing left able to clear it. Every later retract
  /// then answered from it -- true, immediately, having left nothing -- so the
  /// membership stayed advertised, [_current] was never released, and this
  /// account read as busy for the rest of its life: every call refused, every
  /// ring auto-declined.
  ///
  /// `whenComplete` on the assigning side cannot lose that race. The callback
  /// is scheduled as a microtask, which cannot run before the assignment
  /// expression it is part of has finished.
  Future<bool> retract() =>
      _retracting ??= _retract().whenComplete(() => _retracting = null);

  Future<bool> _retract() async {
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
          // Kept, not dropped: giving up waiting does not stop it, and [_leave]
          // is what leaves the next call in this room something to wait for.
          await _leave(session).timeout(_leaveWithin);
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
      // Only while [_current] is still the session THIS retract captured, for
      // the reason spelled out in the `finally` below: a retract sleeps
      // between its retries, and a redial landing in that window is let past
      // join's guard by this very flag. Written unconditionally, a retract
      // that gives up AFTER that redial says "abandoned" about a call that is
      // up and being spoken on -- and the flag is service-wide, so `isBusy`
      // reads false on a live call (a second incoming call can interrupt it)
      // and the next `join` discards it as abandoned. The flag describes one
      // session; it is not ours to write once that session is not the one in
      // hand.
      //
      // Only the SET is guarded, deliberately. Clearing this flag is safe from
      // any caller -- it can only ever free a call that would otherwise be
      // wrongly refused. Guarding the clear the same way would strand a stale
      // `true` whenever [_current] had already moved on, and a stale `true`
      // against a live session is precisely the state that makes `isBusy` read
      // false on a call that is up.
      if (identical(_current, session)) _abandonedMembership = true;
      return false;
    } finally {
      // Released only when the membership was actually taken back. Keeping a
      // session whose leave failed is what gives a later attempt something to
      // retry WITH; a new call is not blocked by it, because join discards it.
      //
      // And only while [_current] is still the session THIS retract captured.
      // Identity is necessary here for the same reason [announceStillHolds]
      // needs more than identity on the other side: a retract outlives the
      // moment it read [_current]. It sleeps between its retries, and a redial
      // landing in that window is let past join's guard by the very abandoned
      // membership this attempt is retrying — so by the time this runs,
      // [_current] can be a call in another room that is up and being spoken
      // on. Clearing it there dropped that call out of the service: isBusy went
      // false with the call still running, a second incoming call could
      // interrupt it, and nothing was left able to retract it.
      if (!_abandonedMembership && identical(_current, session)) {
        _current = null;
        _claimedRoomId = null;
      }
    }
  }

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
  void adoptSessionForTest(GroupCallSession session) => _markCallBegun(session);

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
/// What room state says about anybody else still holding a call here.
enum CallHold {
  /// Somebody else's membership for this call is standing and unexpired.
  held,

  /// Their state is here and none of it holds this call.
  over,

  /// No call state to read yet. Not evidence of anything, and in particular
  /// not evidence that the call the breadcrumb points at has ended.
  unknown,
}

/// What room state says about somebody being in the call we are on.
enum PeerPresence {
  /// A membership of theirs for this call is standing and unexpired.
  live,

  /// They wrote state and none of it puts them in this call -- a retraction,
  /// or a membership that has expired. Positive evidence of a departure.
  gone,

  /// They have written nothing we can see. Not evidence of anything: state
  /// lags a join by seconds, and a room can hold nothing of theirs at all.
  unknown,
}

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

  /// Whether the call being returned to had video. Unknown for an offer
  /// recovered from state alone, which comes back as audio.
  final bool video;

  const RejoinOffer({
    required this.room,
    required this.membershipEventId,
    this.since,
    this.video = false,
  });
}
