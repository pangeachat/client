import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart' show AudioTrack;
import 'package:matrix/matrix.dart' as matrix show Room;
import 'package:matrix/matrix.dart' hide Room;

import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
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

  /// Whether the other person was calling us at the same moment we called them.
  ///
  /// Both sides then believe they placed the call, so both would write it to
  /// the room. Knowing it lets exactly one of them do so — and knowing it from
  /// their ring rather than from an ordering means a call nobody answered,
  /// which only ever runs teardown on the caller's side, is still written.
  bool get peerAlsoPlaced => _peerAlsoPlaced;

  String? _membershipEventId;

  /// This device's membership event for the call.
  ///
  /// The fallback anchor for analytics on a device that neither rang nor was
  /// rung — one joining a call already under way. Without it everything that
  /// device's learner said went uncredited.
  String? get membershipEventId => _membershipEventId;

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

    _wanted = elected;
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
        _capturing = true;
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
  bool _peerArrived = false;
  Timer? _waitingForPeer;

  /// How long a call waits for someone to be on the other end.
  ///
  /// Covers both a callee who never answers and a caller who gave up moments
  /// before this device joined. Without it either leaves a learner sitting in an
  /// open call with an open microphone and nobody there.
  static const _answerWithin = Duration(seconds: 60);

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
      _peerArrived = true;
      _waitingForPeer?.cancel();
      _waitingForPeer = null;
      // The screen decides whether this was a real call from this, so it has to
      // hear about it — the stage does not change when someone answers.
      if (firstArrival && !_disposed) notifyListeners();
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

  void _onDeclined() {
    if (_ending || _peerArrived) return;
    Logs().i('The call was declined');
    _declinedByPeer = true;
    unawaited(hangUp());
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
    try {
      final grant = await _step(() => calls.join(room));
      _joined = true;

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

      // Placing or joining. Someone who was RUNG is answering, whatever the
      // room looks like by the time they get there — deriving it would make a
      // callee whose caller had already hung up look like a new caller and ring
      // them back. For everyone else it is read from the SFU rather than Matrix
      // membership, because a peer who crashed leaves a membership that reads as
      // live for about twelve minutes and would silence a genuine new call.
      final placing = !answering && roster.participants.isEmpty;
      _placed = placing;

      // Elect before announcing, so recording begins with the first word rather
      // than after a round-trip.
      _electRecorder();
      // Settle the first election before announcing, so recording is already
      // running when the peer learns this device is here. Handovers are queued,
      // so without this the initial start would land a microtask later.
      await _step(() => _handover);

      // Whether the peer is already here decides what their later absence
      // means: gone, or simply not answered yet. Read from the roster rather
      // than waited for as an event: someone already in the room when this
      // device joined raises no join event, and that is exactly the person
      // answering a call is joining.
      _peerArrived = roster.hasPeer;
      if (!_peerArrived) {
        _waitingForPeer = Timer(_answerWithin, () {
          if (_ending || _peerArrived) return;
          Logs().i('Nobody joined the call; ending it');
          unawaited(hangUp());
        });
      }

      // announce returns our membership event id, waiting for the state write
      // to echo — the ring needs it, so this is where the wait belongs. Kept,
      // because it is also the only event a device that JOINED a call — with no
      // ring of its own to point at — can anchor its speaking analytics to.
      final membershipId = _membershipEventId = await _step(calls.announce);

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
      // Their ring, if they are calling us at the same time. Subscribed
      // alongside the declines and before our own ring goes out, so a
      // simultaneous call is seen however the two sends interleave.
      _peerRings = calls.ringsIn(room).listen((_) => _peerAlsoPlaced = true);

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
        // Not _step: the id above must be recorded even when we are giving up,
        // because their phone rang and that is what makes this a call worth
        // recording rather than nothing at all.
        _abandonIfEnding();
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
    _to(_declinedByPeer ? CallStage.declined : CallStage.ended);
  }

  /// Ends the call.
  ///
  /// Idempotent and safe to race: a user tapping hang up while the peer's
  /// departure is already tearing the call down joins the same teardown rather
  /// than starting a second one.
  Future<void> hangUp() {
    _ending = true;
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
    unawaited(_declines?.cancel());
    _declines = null;
    unawaited(_peerRings?.cancel());
    _peerRings = null;
    _waitingForPeer?.cancel();
    _waitingForPeer = null;
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

    if (_joined) {
      try {
        // Deliberately still joined when it did not work: a hangup that failed
        // to take the membership back should be tried again rather than
        // remembered as done.
        _joined = !await calls.retract();
      } catch (e, s) {
        Logs().e('Could not retract the call membership', e, s);
      }
    }

    // Drained unconditionally and AFTER retracting. A device displaced moments
    // before the hangup has a stop still unwinding while [_capturing] is already
    // false, so waiting only when it is true would let teardown finish — and the
    // call be written — while that flush was still running.
    _wanted = false;
    try {
      await _handover;
    } catch (_) {}

    // finish, not stop: this is the call ending, not recording moving to
    // another of the learner's devices. Called whether or not this device was
    // the one recording, so the sink is told the audio is complete exactly once.
    try {
      await capture.finish();
    } catch (e, s) {
      Logs().e('Could not flush the call recording', e, s);
    }
    _capturing = false;

    try {
      await media.dispose();
    } catch (e, s) {
      Logs().e('Could not release the call media', e, s);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(hangUp());
    super.dispose();
  }
}
