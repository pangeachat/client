import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart' show AudioTrack;
import 'package:matrix/matrix.dart' as matrix show Room;
import 'package:matrix/matrix.dart' hide Room;

import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/call_roster.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/capture_election.dart';

enum CallStage {
  /// The other person turned the call down. Distinct from ended so the caller
  /// is told why, rather than watching their call stop for no visible reason.
  declined,

  /// Joining the session, connecting media, and starting to record.
  connecting,

  /// Media is flowing and this device is announced to the room.
  connected,

  /// Left cleanly. The recording, if any, has been flushed.
  ended,

  /// Could not be established. Anything partially set up has been torn down.
  failed,
}

/// Thrown when a hangup overtakes a step of coming up.
///
/// Not an error: the user ended the call, and every partially built piece is
/// unwound by the one handler that catches this.
class _Abandoned implements Exception {
  const _Abandoned();
}

/// One call, from tapping Call to hanging up.
///
/// Exists as its own object rather than as widget state because the ordering
/// here is the whole feature: three subsystems come up in a sequence that
/// matters, and they have to come down even when one of them fails. A widget
/// disposing mid-teardown would leave a microphone open or a membership
/// advertised for a call nobody is in.
class ActiveCall extends ChangeNotifier {
  final CallService calls;
  final CallMedia media;
  final CallCaptureService capture;

  CallStage _stage = CallStage.connecting;
  Object? _error;
  bool _joined = false;
  bool _capturing = false;
  Future<void>? _hangUp;
  bool _disposed = false;

  /// Set the moment anything asks the call to end. [start] checks it after every
  /// await, so a hangup that lands mid-connect stops the sequence instead of
  /// racing it to completion.
  bool _ending = false;
  AudioTrack? _track;
  StreamSubscription? _declines;
  String? _notificationId;

  /// Who is actually in the call, per the SFU. The single source of truth for
  /// both presence and the recorder election, so the two can never disagree.
  CallRoster? _roster;
  Future<void> _handover = Future.value();

  /// What the election last decided. Read by [_reconcile] when it runs.
  bool _wanted = false;

  bool _placed = false;

  /// Whether this device started the call rather than joining one.
  ///
  /// Decides which side writes the call to the timeline. Both sides run the
  /// same lifecycle, so without this a two-person call would post two identical
  /// cards to the conversation.
  bool get placedCall => _placed;

  /// The notification this call rang with, once it has been sent.
  String? get notificationEventId => _notificationId;

  StreamSubscription? _peerRings;

  bool _peerAlsoPlaced = false;

  // Watched from a live stream rather than looked up in the room's history, so
  // a ring that arrived in the moment between the call being asked for and this
  // being attached is not seen. The cost is a second copy of the call card in
  // the conversation, on the rare occasion two people call each other in the
  // same instant AND their ring lands in that gap; the alternative is holding a
  // subscription per account for the life of the app, or a history query at the
  // end of every call, to tidy something nobody has reported.

  /// Whether the other person is calling us right now, as opposed to having
  /// called at some point in the past.
  ///
  /// Sync replays old events, and a call from an hour ago is not somebody
  /// calling at the same moment as us. Counting one would make this side stand
  /// aside from writing the call to the room while the other side, not being in
  /// a call at all, never writes it either — so the call would vanish.
  /// When this call began. A ring older than this cannot be somebody calling
  /// at the same moment as us, however recently it was sent.
  DateTime? _startedAt;

  /// How far either side of this call beginning a ring can have been sent and
  /// still be the two of us calling at once.
  ///
  /// Both directions, because both are wrong in the same way. A ring sent
  /// meaningfully BEFORE we began belongs to a call of theirs that already
  /// ended — rings stay valid for a minute and a half, so one they gave up on
  /// is still live when we call them back. A ring sent meaningfully AFTER
  /// belongs to a new call of theirs, placed while we were already in this one.
  /// Neither is the two of us reaching for the phone at the same moment.
  ///
  /// Not zero in either direction: a ring's timestamp is carried in whole
  /// milliseconds while this clock reads in microseconds, so a genuinely
  /// simultaneous ring can round to fractionally either side of the call it is
  /// simultaneous with.
  static const _glareWindow = Duration(seconds: 3);

  void _onPeerRing(Event event) {
    // Deliberately NOT gated on whether they have arrived. In a genuine
    // simultaneous call each side joins the SFU before it rings, so their
    // presence routinely reaches us BEFORE their ring does — and standing that
    // ring down because they were already here left both sides believing they
    // alone had placed the call, so both wrote it and the conversation carried
    // two cards for one call. When the ring was sent is what tells these apart,
    // and it is checked below.
    if (_ending) return;
    final ring = IncomingCallNotification(
      event: event,
      myUserId: calls.client.userID ?? '',
      alreadyJoined: false,
    );
    if (!ring.shouldRing(DateTime.now())) return;
    // And only if it was sent at about the moment this call began. Anything
    // else is a different call of theirs — one they gave up on before we rang
    // back, or a new one placed while we were already in this — and counting
    // either made a side stand aside from writing a call nobody else was
    // writing, so the call was missing from the conversation.
    final began = _startedAt;
    if (began != null) {
      final sent = ring.sentAt;
      if (sent.isBefore(began.subtract(_glareWindow)) ||
          sent.isAfter(began.add(_glareWindow))) {
        return;
      }
    }
    _peerAlsoPlaced = true;
    _peerRingSenderId = event.senderId;
  }

  /// Whether the other person was calling us at the same moment we called them.
  ///
  /// Both sides then believe they placed the call, so both would write it to
  /// the room. Knowing it lets exactly one of them do so — and knowing it from
  /// their ring rather than from an ordering means a call nobody answered,
  /// which only ever runs teardown on the caller's side, is still written.
  bool get peerAlsoPlaced => _peerAlsoPlaced;

  /// Who sent the ring that told us they were calling too.
  ///
  /// The other side of a simultaneous call, named by the one event that proves
  /// it happened. It settles which of the two writes the call when the room
  /// itself cannot say who the other person is.
  String? get peerRingSenderId => _peerRingSenderId;

  String? _peerRingSenderId;

  String? _membershipEventId;

  /// The room this call is in. Kept so the membership can be asked for again
  /// once the call is over, when a device that joined one already under way has
  /// nothing else to anchor its analytics to.
  matrix.Room? _room;

  /// This device's membership event for the call.
  ///
  /// The fallback anchor for analytics on a device that neither rang nor was
  /// rung — one joining a call already under way. Without it everything that
  /// device's learner said went uncredited.
  ///
  /// Asked again if announcing did not see it in time. That wait is deliberately
  /// short so a caller is never left hanging, but by the time a call is over the
  /// membership has long since arrived.
  String? get membershipEventId {
    final known = _membershipEventId;
    if (known != null) return known;
    final room = _room;
    if (room == null) return null;
    return _membershipEventId = calls.membershipEventIdIn(room);
  }

  ActiveCall({required this.calls, required this.media, required this.capture});

  /// Starts or stops recording to match which device should be recording now.
  ///
  /// Runs whenever the call's participants change, because that is the only thing
  /// that can change the answer. Idempotent — re-running it in the right state
  /// does nothing — so it is safe to call on every event.
  /// Re-runs the participant handler now, for tests, as a roster change would.
  @visibleForTesting
  Future<void> tickReelectionForTest() async {
    _onParticipantsChanged();
    await _handover;
    // A peer-gone tick triggers an unawaited hangup; wait it out so a test sees
    // the settled state.
    await _hangUp;
  }

  void _electRecorder() {
    if (_ending) return;
    final track = _track;
    if (track == null) return;

    final me = calls.client.deviceID ?? '';
    final elected = CaptureElection(
      myDeviceId: me,
      // Siblings only, from the SFU's own participant list. The election has to
      // agree with presence about who is in the call; reading a different source
      // would let it defer to a device that is not actually here.
      siblingDeviceIds: (_roster?.siblingDeviceIds ?? const <String>[]).where(
        (id) => id != me,
      ),
    ).shouldRecord;

    // Only while there is somebody who can actually hear it. A caller talking
    // while it rings is talking to nobody, and so is one talking through a
    // dropped connection — the roster deliberately holds its last picture
    // across a reconnect so a blip does not end the call, which means presence
    // alone still reads as somebody being there. Either way the words went
    // nowhere, and crediting them would put speech in a learner's analytics
    // that no one ever heard.
    _wanted = elected && _peerArrived && (_roster?.isConnected ?? false);
    // Handovers are serialised. A device can be displaced and reinstated faster
    // than a flush completes, and starting a new recording while the previous
    // stop is still unwinding would let that stop cancel the new tap and close
    // its sink underneath it.
    _handover = _handover.then((_) => _reconcile(track));
  }

  /// Brings what is actually recording into line with what should be.
  ///
  /// Reads the wanted state when it RUNS rather than when it was queued, so a
  /// device displaced and reinstated while a flush unwinds settles on the latest
  /// answer instead of replaying a stale one. [_capturing] moves only once the
  /// change has actually happened, so a tap that fails to open is retried by the
  /// next election rather than remembered as open.
  Future<void> _reconcile(AudioTrack track) async {
    final wanted = _wanted && !_ending;
    if (wanted == _capturing) return;
    try {
      if (wanted) {
        // Awaited: attaching a tap is a platform call that can fail, and
        // recording this as capturing before it succeeded would leave the
        // election believing a device is recording when it is not.
        await capture.start(track);
        // Read back rather than assumed. A device with no point to record from
        // returns without attaching one, and calling that "recording" would stop
        // every later election from trying again.
        _capturing = capture.isRecording;
        Logs().i('Recording this call on this device');
      } else {
        await capture.stop();
        _capturing = false;
        Logs().i('Another device of this account is recording this call');
      }
    } catch (e, s) {
      // Recording is not the call. A tap that will not open, or will not close,
      // costs analytics — it must never take down a conversation.
      Logs().e('Could not change recording state', e, s);
    }
  }

  /// True once the peer has been seen in the call.
  ///
  /// Their absence only means the call is over if they were ever there — before
  /// that it just means they have not answered yet.
  /// When they arrived. This IS the latch: a call cannot have had somebody on
  /// it without a moment they arrived, and keeping the two as separate fields is
  /// what let a call be recorded as answered with a duration of zero.
  DateTime? _talkStartedAt;

  /// When the talking stopped — the moment the call was ended or they left, not
  /// the moment teardown finished. Retracting the membership, flushing the last
  /// chunk of audio and waiting for it to be transcribed take seconds, and none
  /// of that is time anybody spent talking.
  DateTime? _talkEndedAt;

  bool get _peerArrived => _talkStartedAt != null;

  /// Notes that somebody is on the other end. Every route to that fact goes
  /// through here, so the moment is always recorded with it.
  void _notePeerPresent() => _talkStartedAt ??= DateTime.now();

  /// Notes that the talking is over. Called as the call starts to end rather
  /// than when it has finished ending.
  void _noteTalkEnded() => _talkEndedAt ??= DateTime.now();

  Timer? _waitingForPeer;

  /// How long a call waits for someone to be on the other end.
  ///
  /// Covers both a callee who never answers and a caller who gave up moments
  /// before this device joined. Without it either leaves a learner sitting in an
  /// open call with an open microphone and nobody there.
  static final _answerWithin =
      CallNotification.lifetime + const Duration(seconds: 15);

  /// How long someone answering waits for the caller they are answering. Short,
  /// because the caller should already be there; this only covers the moment it
  /// takes their presence to reach us.
  static const _joinWithin = Duration(seconds: 10);

  /// Fires the give-up now instead of after the wait. Sixty seconds of real
  /// time in a test proves nothing the timer's own logic does not.
  @visibleForTesting
  Future<void> waitForPeerTimeoutForTest() async {
    final waiting = _waitingForPeer;
    if (waiting == null || !waiting.isActive) return;
    waiting.cancel();
    _waitingForPeer = null;
    if (_ending || _peerArrived) return;
    await hangUp();
  }

  void _onParticipantsChanged() {
    if (_ending) return;

    // From the SFU, which is the only thing that knows who is actually here.
    // Matrix membership cannot answer this: it is room state on a multi-minute
    // expiry, so it lags a join by seconds and a crash by minutes. The roster
    // holds its last picture while the connection is down, so a reconnect —
    // which empties and refills the participant list — does not read as the
    // other person hanging up.
    final peerHere = _roster?.hasPeer ?? false;
    if (peerHere) {
      final firstArrival = !_peerArrived;
      _notePeerPresent();
      _waitingForPeer?.cancel();
      _waitingForPeer = null;
      // The screen decides whether this was a real call from this, so it has to
      // hear about it — the stage does not change when someone answers.
      if (firstArrival && !_disposed) notifyListeners();
      // Taken here as well, because this runs throughout the call while the
      // teardown read happens once. A membership whose echo was still on its
      // way at that single moment left a device with nothing to anchor its
      // analytics to, and every word its learner spoke was dropped.
      _rememberMembership();
    } else if (_peerArrived) {
      // In a direct message there is nobody else to wait for. Staying would hold
      // a microphone open for a conversation that has ended, and the learner
      // would have to notice and hang up on silence.
      Logs().i('The other participant left; ending the call');
      unawaited(hangUp());
      return;
    }

    _electRecorder();
  }

  /// Notes this device's own membership event once the room has echoed it.
  ///
  /// It is what a device that JOINED a call — with no ring of its own to point
  /// at — anchors its speaking analytics to, and it can only be read while the
  /// session is still here.
  void _rememberMembership() {
    if (_membershipEventId != null) return;
    final room = _room;
    if (room == null) return;
    _membershipEventId = calls.membershipEventIdIn(room);
  }

  /// Declines seen before this call knew which notification was its own.
  ///
  /// The subscription is deliberately older than the id it matches, so a
  /// decline can arrive while the ring's own send is still returning. Dropping
  /// it would leave the caller sitting through the full ring having already
  /// been turned down.
  final Set<String> _declinedBefore = {};

  /// A decline seen in the room, matched against our own call HERE rather than
  /// when subscribing.
  void _onDeclineEvent(Event event) {
    final target = calls.declineTarget(event);
    if (target == null) return;
    final ours = _notificationId;
    if (ours == null) {
      // Remembered, not acted on. Without our own ring's id there is no way to
      // tell WHICH call a decline turned down, and guessing has now been wrong
      // twice: first a decline replayed out of history ended a call as it
      // started, then a decline of the previous ring ended a redial. The ring is
      // sent with a stable id and tried twice, so losing that id is rare — and
      // when it happens the caller rings out instead of being told, which is a
      // far smaller price than a call that hangs itself up.
      _declinedBefore.add(target);
      return;
    }
    if (target != ours) return;
    _onDeclined();
  }

  /// Replays a decline that arrived before this call had an id to match it to.
  void _catchUpOnDeclines() {
    final ours = _notificationId;
    if (ours != null && _declinedBefore.remove(ours)) _onDeclined();
  }

  /// How long a decline waits to see whether somebody answers anyway.
  ///
  /// A phone and a laptop both ring. Turning the call down on one while
  /// answering on the other sends a decline that can reach the caller before
  /// the answer does — the decline is a timeline event, the answer is a join
  /// the SFU has to report — and acting on it immediately hung up a call that
  /// had just been answered, and recorded it as turned down.
  static const _declineLosesTo = Duration(milliseconds: 1500);

  Timer? _decliding;

  void _onDeclined() {
    if (_ending || _peerArrived || _decliding != null) return;
    Logs().i('The call was declined');
    _decliding = Timer(_declineLosesTo, () {
      _decliding = null;
      // Re-read, not remembered. Somebody arriving in this window means the
      // call was answered on another of their devices, and an answered call is
      // not a declined one.
      if (_ending || _peerArrived) return;
      _declinedByPeer = true;
      unawaited(hangUp());
    });
  }

  /// Acts on a pending decline now instead of after the wait.
  @visibleForTesting
  Future<void> declineTimeoutForTest() async {
    final pending = _decliding;
    if (pending == null || !pending.isActive) return;
    pending.cancel();
    _decliding = null;
    if (_ending || _peerArrived) return;
    _declinedByPeer = true;
    await hangUp();
  }

  bool _declinedByPeer = false;

  /// Whether the other person turned the call down.
  bool get wasDeclined => _declinedByPeer;

  /// Whether anyone was ever actually on the other end.
  ///
  /// Connected means this device reached the SFU, not that a conversation
  /// happened. A call that rang out unanswered is not a call, and writing one
  /// would credit a learner for talking to nobody.
  bool get hadPeer => _peerArrived;

  /// When the conversation started, for the timer on screen. Null until
  /// somebody is on the other end — ringing is not talking.
  DateTime? get talkStartedAt => _talkStartedAt;

  /// How long the two sides were actually both on the call.
  ///
  /// Kept here rather than measured by the screen because this is what knows
  /// when they arrived and when the call began to end. The screen only sees
  /// stage changes, and the last of those lands after teardown — so measuring
  /// there charged the conversation for the flush and the upload that follow it.
  Duration get talkDuration {
    final from = _talkStartedAt;
    if (from == null) return Duration.zero;
    return (_talkEndedAt ?? DateTime.now()).difference(from);
  }

  CallStage get stage => _stage;
  Object? get error => _error;
  bool get isRecording => _capturing;

  void _to(CallStage next, [Object? error]) {
    if (_stage == next && error == null) return;
    _stage = next;
    _error = error;
    // Teardown is asynchronous and [dispose] starts it, so the final transition
    // to ended routinely lands after this notifier is gone. Notifying then
    // throws, and it would throw on the ordinary path of closing the call
    // screen.
    if (_disposed) return;
    notifyListeners();
  }

  /// Brings the call up.
  ///
  /// The order is deliberate. Media connects before this device announces
  /// itself, so a peer never sees a participant who cannot yet be heard, and
  /// recording starts before the announcement too — otherwise the first seconds
  /// of a call, which is exactly when people speak, would go uncredited.
  ///
  /// A failure at any step tears down the steps that already succeeded. The call
  /// either exists completely or not at all.
  /// Places or joins a call.
  ///
  /// Whether this rings the other side is NOT a caller's choice — it is a fact
  /// about the room. A call another user is already in is one this device is
  /// joining, so it must not ring; a room with no other user in a call is one
  /// this device is starting, so it rings. Deriving it here rather than taking a
  /// flag means no call site — the header button, the banner, a deep link — can
  /// get it wrong, and keying it on ANOTHER user rather than any active call
  /// means this account's own stale membership does not silence a real call.
  ///
  /// Keyed on another DEVICE, not another user, so this device's own stale
  /// membership (replaced by the new join) and its own second device joining
  /// are both handled.
  Future<void>? _starting;

  /// Completes once coming up has finished unwinding, however it ended.
  ///
  /// Deliberately NOT awaited by [hangUp]: tearing down must never wait on the
  /// network, or hanging up would stall for as long as a request in flight and
  /// hold the microphone open. What this is for is the RECORD — whether the
  /// other side was rung is only final once start has settled, and a call that
  /// rang somebody must not be written as though it never happened.
  Future<void> get settled => _starting ?? Future.value();

  /// [answering] is ground truth from the call site: this device was rung, so
  /// it is joining whatever the state of the room looks like. Everything else
  /// is derived, because no other call site can know.
  Future<void> start(
    matrix.Room room, {
    required bool video,
    bool answering = false,
  }) => _starting = _start(room, video: video, answering: answering);

  /// Runs one step of coming up, and gives up if a hangup has landed.
  ///
  /// Checked on BOTH sides of the await. Coming up is a sequence of network
  /// round-trips and a hangup can land inside any of them, so every step needs
  /// the same guard — and requiring each one to remember it is what made this
  /// class of bug recur: a step added later simply would not have it. Going
  /// through here means the guard cannot be left out.
  Future<T> _step<T>(Future<T> Function() run) async {
    if (_ending) throw const _Abandoned();
    final result = await run();
    if (_ending) throw const _Abandoned();
    return result;
  }

  /// Gives up here if a hangup has landed, for the one step that must record
  /// its result before deciding whether to continue.
  void _abandonIfEnding() {
    if (_ending) throw const _Abandoned();
  }

  Future<void> _start(
    matrix.Room room, {
    required bool video,
    required bool answering,
  }) async {
    _room = room;
    _startedAt = DateTime.now();
    // Subscribed before anything else. Two people calling at the same moment is
    // decided by seeing their ring, and the window this has to cover starts when
    // ours does — not when our media happens to be ready.
    _peerRings = calls.ringsIn(room).listen(_onPeerRing);
    try {
      // NOT through the guarded step. Joining leaves the service holding the
      // call, so that has to be written down before anything decides to give up
      // — a hangup landing in between skipped the retract, and the service then
      // believed it was still in a call and refused every later one.
      // Taken before the call: whatever attempt number the service is on when
      // we ask is the one our join becomes, and it is what lets us give up OUR
      // join later rather than whichever happens to be running by then.
      _joinAttempt = calls.joinAttempt + 1;
      final grant = await calls.join(room);
      _joined = true;
      _abandonIfEnding();

      await _step(() => media.connect(grant, video: video));

      _track = media.publishedAudio;
      if (_track == null) {
        // The call is still worth having without analytics; a call that refuses
        // to connect because it cannot be recorded is the worse failure.
        Logs().w('Call has no published audio track; not recording');
      }

      // The SFU's own participant list, read as state. Subscribed to before
      // the first election so no change between the two is missed, and the
      // whole picture is recomputed on every notification — so a missed
      // notification costs nothing rather than leaving a tally adrift.
      //
      // This replaces both a Matrix membership subscription and a 30-second
      // poll. Membership is room state on a multi-minute expiry: it lags a join
      // and cannot see a crash until it lapses, which is why the poll existed
      // at all. The SFU knows immediately, so neither is needed.
      final roster = media.roster(myUserId: calls.client.userID ?? '');
      _roster = roster;
      roster.addListener(_onParticipantsChanged);

      // Placing or joining. Someone who was RUNG is answering, whatever the room
      // looks like by the time they get there — deriving that would make a
      // callee whose caller had already hung up look like a new caller and ring
      // them back. For everyone else it is read from the SFU rather than Matrix
      // membership, because a peer who crashed leaves a membership that reads as
      // live for about twelve minutes and would silence a genuine new call.
      //
      // Two people calling each other in the very same instant can each see the
      // other arrive before they look, and both then take themselves for a
      // joiner — so neither writes the call and it is missing from the
      // conversation. Deciding this without the roster was tried and is worse:
      // it makes a SECOND DEVICE of the same account, and anyone joining a call
      // already under way, write a card of their own, which are the ordinary
      // cases rather than a sub-millisecond overlap.
      final placing = !answering && roster.participants.isEmpty;
      _placed = placing;

      // Read before anything is awaited. A peer who was already here can leave
      // while the first handover settles, and reading afterwards would have this
      // call believe nobody ever answered — no teardown when they left, and the
      // conversation recorded as unanswered.
      if (roster.hasPeer) _notePeerPresent();

      // Elect before announcing, so recording begins with the first word rather
      // than after a round-trip.
      _electRecorder();
      // Settle the first election before announcing, so recording is already
      // running when the peer learns this device is here. Handovers are queued,
      // so without this the initial start would land a microtask later.
      await _step(() => _handover);
      // announce returns our membership event id, waiting for the state write
      // to echo — the ring needs it, so this is where the wait belongs. Kept,
      // because it is also the only event a device that JOINED a call — with no
      // ring of its own to point at — can anchor its speaking analytics to.
      // NOT through the guarded step, for the same reason the ring below is
      // not: the id must be recorded even when we are giving up. Through it,
      // a hangup landing inside the announce threw after the id had come back
      // but before it was kept, and a device with no ring of its own then had
      // nothing to anchor its learner's words to.
      final membershipId = _membershipEventId = await calls.announce();
      _abandonIfEnding();

      // Ring the other side, if we are the one placing the call. A timeline
      // event, so it reaches them via push even if their app was closed —
      // membership alone could not. Its id is what a decline points back at, so
      // we keep it to match one. The answerer does not ring: a notification from
      // them would ring the caller, who is already here.
      // Subscribed BEFORE the ring goes out. A decline can only follow the
      // ring, but our own send has not necessarily returned by the time the
      // callee acts, and a stream with no replay drops anything that lands in
      // that gap — the caller would then sit through the whole ring instead of
      // being told they were turned down.
      _declines = calls.declinesIn(room).listen(_onDeclineEvent);
      if (placing && membershipId != null) {
        // Assigned before the check, so a hangup landing here still knows the
        // other side was rung — their phone rang, and that is what makes this a
        // call worth recording rather than nothing at all.
        _notificationId = await calls.ring(
          room,
          membershipEventId: membershipId,
          video: video,
        );
        // A decline can beat our own send home; replay one if it did.
        _catchUpOnDeclines();
        // A hangup landing inside the send above moves the stage to ended
        // before this line runs, and nothing changes state afterwards. The
        // record does not depend on one: it waits on [settled], which is this
        // whole sequence unwinding, so the id assigned above is always in hand
        // by the time the call is written.
        // Not _step: the id above must be recorded even when we are giving up,
        // because their phone rang and that is what makes this a call worth
        // recording rather than nothing at all.
        _abandonIfEnding();
      }

      // Only now. Announcing waits for a state write to echo and ringing is
      // another round-trip, and starting the clock before either meant the
      // caller's patience was spent on its own setup: a slow network could have
      // it give up and write a missed call while the callee's phone was still
      // ringing and could still be answered.
      if (!_peerArrived) {
        // Someone answering a call has somebody to answer; if nobody is there,
        // the caller has already gone and waiting a full minute only holds the
        // microphone open in an empty call. Someone placing one is waiting for
        // an answer, which is what the longer wait is for.
        final wait = answering ? _joinWithin : _answerWithin;
        _waitingForPeer = Timer(wait, () {
          if (_ending || _peerArrived) return;
          Logs().i('Nobody joined the call; ending it');
          unawaited(hangUp());
        });
      }

      // State may have moved while announcing. Awaited too, so start() leaves
      // nothing queued — a reconcile still pending when a hangup arrives would
      // run inside teardown and stop the recording before the membership was
      // retracted, delaying what the peer sees by the length of a flush.
      _electRecorder();
      await _step(() => _handover);

      _to(CallStage.connected);
    } on _Abandoned {
      // The user ended the call while it was coming up. Every piece already
      // built is unwound here, once, for whichever step gave up.
      return _abandon();
    } on AlreadyInACall {
      // Never held the account's claim, so it must not be given up here — that
      // would cancel the join that DOES hold it, which is somebody else's call
      // coming up.
      _joinAttempt = null;
      rethrow;
    } catch (e, s) {
      if (_ending) {
        // Tearing down underneath a step in flight is what made it throw, so
        // this is the same abandonment arriving as somebody else's error.
        // Telling the user their call failed would be untrue.
        Logs().d('Call abandoned while coming up: $e');
        return _abandon();
      }
      Logs().e('Could not start the call', e, s);
      await _tearDown();
      _to(CallStage.failed, e);
    }
  }

  /// Unwinds a call that was asked to end while it was still coming up.
  ///
  /// Connecting takes network round-trips, and a user who closes the screen
  /// during them must not end up in a call that finishes assembling itself
  /// behind a dismissed page.
  Future<void> _abandon() async {
    await _tearDown();
    // Again, and deliberately. Whether there is a call to give back can become
    // true WHILE teardown is running — a hangup landing as the join returns —
    // and a teardown already in flight has passed that question by. Skipping it
    // left the service holding a call it would never be asked to release, and
    // every later call refused.
    await _releaseCall();
    _to(_declinedByPeer ? CallStage.declined : CallStage.ended);
  }

  /// Ends the call.
  ///
  /// Idempotent and safe to race: a user tapping hang up while the peer's
  /// departure is already tearing the call down joins the same teardown rather
  /// than starting a second one.
  Future<void> hangUp() {
    _ending = true;
    _noteTalkEnded();
    return _hangUp ??= () async {
      try {
        await _tearDown();
        _to(_declinedByPeer ? CallStage.declined : CallStage.ended);
      } finally {
        // A teardown that could not retract must not be remembered as done.
        // Memoizing it would make every later hangup return this same finished
        // future, so the membership would stay advertised until it expired with
        // nothing able to take it back.
        if (_joined) _hangUp = null;
      }
    }();
  }

  /// Gives the call back to the service.
  ///
  /// Its own step, because whether there is one to give back is not settled when
  /// teardown starts: a hangup can land in the moment between the join returning
  /// and this call knowing about it. Idempotent, and safe to ask twice.
  Future<void> _releaseCall() =>
      _releasing ??= _release().whenComplete(() => _releasing = null);

  Future<void>? _releasing;

  /// The service's join attempt this call owns, if it got that far.
  int? _joinAttempt;

  Future<void> _release() async {
    if (!_joined) {
      // No membership to take back — the join never came back. The service is
      // still holding this account's one call for it, though, and until that is
      // handed over every incoming ring is suppressed and every new call
      // refused, with the screen already closed.
      final attempt = _joinAttempt;
      if (attempt != null) calls.abandonJoin(attempt);
      return;
    }
    try {
      // Deliberately still joined when it did not work: a hangup that failed to
      // take the membership back should be tried again rather than remembered
      // as done.
      _joined = !await calls.retract();
    } catch (e, s) {
      Logs().e('Could not retract the call membership', e, s);
    }
  }

  /// Unwinds whatever is up, and never gives up partway.
  ///
  /// **Membership is retracted first**, not last. It is the only part of
  /// teardown the peer can see, and everything after it is local work that can
  /// be slow — flushing a recording waits on chunk delivery. Unwinding in strict
  /// reverse would leave this device advertised as a participant for as long as
  /// an upload took, so the peer would see someone who had already hung up.
  ///
  /// The rest still runs in reverse. Recording stops before media is released,
  /// because the tap lives on the track that releasing it destroys.
  ///
  /// Every step is isolated: a recording that fails to flush must not leave the
  /// microphone open, and a socket that fails to close must not leave the
  /// membership standing.
  /// In flight, so a hangup and an abandoned start join one unwind rather than
  /// running two at once. Cleared on completion, because a teardown that could
  /// not retract must still be retryable.
  Future<void>? _tearingDown;

  Future<void> _tearDown() =>
      _tearingDown ??= _unwind().whenComplete(() => _tearingDown = null);

  Future<void> _unwind() async {
    _ending = true;
    _noteTalkEnded();
    unawaited(_declines?.cancel());
    _declines = null;
    unawaited(_peerRings?.cancel());
    _peerRings = null;
    _waitingForPeer?.cancel();
    _waitingForPeer = null;
    // A decline waiting out its grace when teardown arrives still happened.
    // Only the WAIT is abandoned, not the fact — otherwise a decline landing in
    // the last moment before the call gives up on its own is written as nobody
    // answering, when somebody did answer: they said no.
    if (_decliding != null && !_peerArrived) _declinedByPeer = true;
    _decliding?.cancel();
    _decliding = null;
    try {
      // Detached synchronously so nothing else arrives, but disposed only once
      // the current notification has unwound. Teardown is routinely triggered BY
      // a roster notification — the peer leaving — and disposing a notifier
      // while it is still walking its listener list is how that becomes a crash.
      final roster = _roster;
      _roster = null;
      roster?.removeListener(_onParticipantsChanged);
      if (roster != null) scheduleMicrotask(roster.dispose);
    } catch (e, s) {
      // Every step of teardown is isolated. An error here once aborted the whole
      // unwind, leaving the membership advertised and the call unrecorded.
      Logs().w('Could not stop watching participants', e, s);
    }

    // Read while the session is still here. Retracting releases it, and the
    // membership can no longer be matched to this call afterwards — which is
    // exactly when a device that joined one already under way needs it.
    _rememberMembership();

    // Drained unconditionally and BEFORE retracting. A device displaced moments
    // before the hangup has a stop still unwinding while [_capturing] is already
    // false, so waiting only when it is true would let teardown finish — and the
    // call be written — while that flush was still running.
    _wanted = false;
    try {
      await _handover;
    } catch (_) {}

    // Stop first: the tap comes off and the last of the audio is handed to the
    // uploader. Nothing more will be recorded after this returns.
    try {
      await capture.stop();
    } catch (e, s) {
      Logs().e('Could not flush the call recording', e, s);
    }
    _capturing = false;

    // Then the microphone and camera — and this is also what the other person
    // sees. Their client reads who is present from the SFU, not from Matrix
    // room state, so leaving the SFU is what tells them we have gone; the
    // membership below is bookkeeping they never look at. Retracting first, as
    // this once did, left them still hearing a learner who had hung up for as
    // long as that state write took, and finishing waits for uploads and
    // transcription, which can take a minute.
    try {
      await media.dispose();
    } catch (e, s) {
      Logs().e('Could not release the call media', e, s);
    }

    // One more look before the session goes. The echo can land at any point
    // during teardown, and after the retract the membership can no longer be
    // matched to this call — which is exactly when a device that joined one
    // already under way has nothing else to anchor its learner's words to.
    _rememberMembership();

    // The membership last. Nobody is waiting on it — the peer already saw us
    // leave — and it is the one step that can be retried later if the server
    // refuses, so it costs nothing to do it once the devices are free.
    await _releaseCall();

    // Last, with the devices already released: tell the recording the call is
    // over and let what is in flight land.
    try {
      await capture.finish();
    } catch (e, s) {
      Logs().e('Could not settle the call recording', e, s);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(hangUp());
    super.dispose();
  }
}
