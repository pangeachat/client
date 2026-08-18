import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart' show AudioTrack;
import 'package:matrix/matrix.dart' as matrix show Room;
import 'package:matrix/matrix.dart' hide Room;

import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
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
  matrix.Room? _room;

  /// Set the moment anything asks the call to end. [start] checks it after every
  /// await, so a hangup that lands mid-connect stops the sequence instead of
  /// racing it to completion.
  bool _ending = false;
  AudioTrack? _track;
  StreamSubscription? _participants;
  StreamSubscription? _declines;
  Timer? _reelect;
  String? _notificationId;
  Future<void> _handover = Future.value();

  /// What the election last decided. Read by [_reconcile] when it runs.
  bool _wanted = false;

  ActiveCall({required this.calls, required this.media, required this.capture});

  /// Starts or stops recording to match which device should be recording now.
  ///
  /// Runs whenever the call's participants change, because that is the only thing
  /// that can change the answer. Idempotent — re-running it in the right state
  /// does nothing — so it is safe to call on every event.
  /// Fires the periodic re-election now, for tests, instead of on the timer.
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
      // Siblings only. The election always counts the caller itself, so passing
      // this device's own id would be harmless — filtering keeps the argument
      // honest to its name.
      siblingDeviceIds: calls.myDeviceIdsInCall.where((id) => id != me),
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
        capture.start(track);
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
    final room = _room;

    // From room state with expiry, not the SDK's participant set: that set only
    // rebuilds on a membership event, so a peer who crashed without leaving
    // would still read as present. A live membership from the peer does not.
    final peerHere = room != null && calls.otherUserInCall(room);
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
  Future<void> start(matrix.Room room, {required bool video}) async {
    _room = room;
    final placing = !calls.otherDeviceInCall(room);
    try {
      final grant = await calls.join(room);
      _joined = true;
      if (_ending) return _abandon();

      await media.connect(grant, video: video);
      if (_ending) return _abandon();

      _track = media.publishedAudio;
      if (_track == null) {
        // The call is still worth having without analytics; a call that refuses
        // to connect because it cannot be recorded is the worse failure.
        Logs().w('Call has no published audio track; not recording');
      }

      // Subscribe FIRST. The SDK's event stream is a plain broadcast, so a
      // membership change between electing and subscribing would simply be
      // missed — and this device would keep recording alongside a sibling, or
      // stay silent as the only one left.
      _participants = calls.callEvents?.listen((_) => _onParticipantsChanged());

      // Then elect, before announcing, so recording begins with the first word
      // rather than after a round-trip. The election reads room state, which
      // already lists any other device of this account.
      _electRecorder();

      // Re-run periodically as well as on participant changes. A sibling device
      // that crashed leaves a membership that lapses on a timer, not an event,
      // so without this a device deferring to that phantom would stay silent for
      // the rest of the call. The tick drops it once it expires and this device
      // takes over recording.
      // Runs the full change handler, not just the election, because a
      // membership lapses on a timer rather than an event: a crashed sibling
      // that deferred recording, or a crashed PEER who leaves with no departure
      // event, would otherwise go unnoticed — the mic held open for a
      // conversation that ended. The tick catches both.
      _reelect = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _onParticipantsChanged(),
      );
      // Settle the first election before announcing, so recording is already
      // running when the peer learns this device is here. Handovers are queued,
      // so without this the initial start would land a microtask later.
      await _handover;

      // Whether the peer is already here decides what their later absence
      // means: gone, or simply not answered yet.
      _peerArrived = calls.hasRemoteParticipants;
      if (!_peerArrived) {
        _waitingForPeer = Timer(_answerWithin, () {
          if (_ending || _peerArrived) return;
          Logs().i('Nobody joined the call; ending it');
          unawaited(hangUp());
        });
      }

      // announce returns our membership event id, waiting for the state write
      // to echo — the ring needs it, so this is where the wait belongs.
      final membershipId = await calls.announce();
      if (_ending) return _abandon();

      // Ring the other side, if we are the one placing the call. A timeline
      // event, so it reaches them via push even if their app was closed —
      // membership alone could not. Its id is what a decline points back at, so
      // we keep it to match one. The answerer does not ring: a notification from
      // them would ring the caller, who is already here.
      if (placing && membershipId != null) {
        _notificationId = await calls.ring(
          room,
          membershipEventId: membershipId,
          video: video,
        );
      }
      if (_notificationId != null) {
        _declines = calls
            .declinesOf(room, _notificationId!)
            .listen((_) => _onDeclined());
      }

      // State may have moved while announcing. Awaited too, so start() leaves
      // nothing queued — a reconcile still pending when a hangup arrives would
      // run inside teardown and stop the recording before the membership was
      // retracted, delaying what the peer sees by the length of a flush.
      _electRecorder();
      await _handover;

      _to(CallStage.connected);
    } catch (e, s) {
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
  Future<void> _tearDown() async {
    _ending = true;
    _reelect?.cancel();
    _reelect = null;
    unawaited(_declines?.cancel());
    _declines = null;
    _waitingForPeer?.cancel();
    _waitingForPeer = null;
    try {
      await _participants?.cancel();
    } catch (e, s) {
      // Every step of teardown is isolated. An error here once aborted the whole
      // unwind, leaving the membership advertised and the call unrecorded.
      Logs().w('Could not stop watching participants', e, s);
    }
    _participants = null;

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

    if (_capturing) {
      _capturing = false;
      try {
        await capture.stop();
      } catch (e, s) {
        Logs().e('Could not flush the call recording', e, s);
      }
    }

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
