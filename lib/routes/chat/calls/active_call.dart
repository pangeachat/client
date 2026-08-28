import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart' show AudioTrack;
import 'package:matrix/matrix.dart' as matrix show Room;
import 'package:matrix/matrix.dart' hide Room;

import 'package:fluffychat/routes/chat/calls/call_breadcrumb.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/call_roster.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/capture_election.dart';

import 'package:pangea_call_capture/pangea_call_capture.dart'
    show CallForegroundControl;

/// How a call finished, latched the moment ending BEGINS rather than when
/// teardown completes.
///
/// The stage only reaches its terminal value after the whole unwind — retract,
/// tap detach, upload settling — which is seconds. A screen that waits for the
/// stage therefore feels dead after the button is pressed and keeps counting
/// after the peer has hung up. The outcome is the same fact, available at once.
enum CallOutcome { ended, declined, failed }

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

  /// Whether this call ATTEMPTED to ring the other side — set the moment the
  /// send begins, kept even if both responses are lost. See the record's
  /// "mattered" decision.
  bool get rangOut => _rangOut;
  bool _rangOut = false;

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
    //
    // Measured in ONE clock, and that clock is ours. Glare is not really a
    // question about when the two rings were STAMPED -- it is "did their ring
    // reach us while we were placing ours", and both halves of that are
    // observable here without asking anybody else's clock: `_startedAt` is
    // when we began, and now is when their ring arrived. Comparing our local
    // start against a timestamp from their device, or from the server, is a
    // comparison across clocks that no skew allowance can make sound: a
    // device two minutes fast fell outside a three-second window, so ONE side
    // saw the glare and the other did not, and a single call was written to
    // the room twice.
    final began = _startedAt;
    if (began != null && DateTime.now().isAfter(began.add(_glareWindow))) {
      return;
    }
    // And EVIDENCE, not just timing: the device that rang is still holding a
    // call. Arrival time alone cannot tell a ring sent a moment ago from one
    // sent twenty seconds ago and delivered now -- a call of theirs that
    // already ended stays valid for its whole lifetime, and counting it made
    // this side stand aside from writing a call the other side was not
    // writing either. Their membership answers it without reference to any
    // clock: somebody mid-call is still in the room's state, somebody who
    // gave up is not.
    final room = _room;
    if (room != null &&
        calls.callerPresence(
              room,
              event.senderId,
              deviceId: ring.senderDeviceId,
            ) ==
            PeerPresence.gone) {
      return;
    }
    _peerAlsoPlaced = true;
    _peerRingSenderId = event.senderId;
    // Their ring names THEIR membership -- on glare, whichever side loses the
    // tie-break stamps the winner's membership as the call's identity, and
    // this is the only place the loser ever learns it.
    _peerRingMembershipId = ring.membershipEventId;
  }

  /// Moves this call's start back, so a test can put a ring's ARRIVAL late
  /// without waiting for the clock. Glare is judged on when their ring
  /// reached us relative to when we began, and both are local.
  @visibleForTesting
  void backdateStartForTest(Duration by) {
    final began = _startedAt;
    if (began != null) _startedAt = began.subtract(by);
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

  /// The membership event the peer's simultaneous ring pointed at, when there
  /// was one. The glare loser's route to the call's shared identity.
  String? get peerRingMembershipId => _peerRingMembershipId;

  String? _peerRingMembershipId;

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
  /// The membership that IDENTIFIES this call, as opposed to the one that is
  /// currently live.
  ///
  /// They are the same thing except after a rejoin, where the returning
  /// process must publish a fresh membership -- that is what renews the
  /// refresh and the delayed leave -- while the call it returned to keeps the
  /// identity it already had. Everything keyed on the call itself (its card,
  /// the speech credited to it) uses this, so a reload does not split one
  /// call into two records; everything about being present right now uses
  /// [membershipEventId].
  String? get callAnchorId => _rejoinAnchorId ?? membershipEventId;

  String? _rejoinAnchorId;

  String? get membershipEventId {
    final known = _membershipEventId;
    if (known != null) return known;
    final room = _room;
    if (room == null) return null;
    return _membershipEventId = calls.membershipEventIdIn(room);
  }

  ActiveCall({
    required this.calls,
    required this.media,
    required this.capture,
    CallForegroundControl? foreground,
  }) : _foreground = foreground;

  /// The Android foreground service that keeps the call alive off-screen.
  /// Null on every platform that needs none.
  final CallForegroundControl? _foreground;

  /// Whether the service refused the first start -- the microphone permission
  /// dialog was still up -- and is owed a retry at the first post-grant step.
  bool _foregroundPending = false;

  /// Whether THIS call is the one the service runs for -- the PLATFORM'S
  /// answer, not this side's guess: the native start adjudicates on the one
  /// thread every start arrives on, so of two racing calls exactly one hears
  /// yes. Only the claimant may stop the service, or a refused second call's
  /// teardown would strip the live call of its background protection.
  bool _foregroundClaimed = false;

  /// The action-handler claim, for the same reason on the Dart side: the
  /// handler slot is global, and an old session disposing late must not
  /// clear the one a new call installed.
  int? _actionEpoch;

  /// What the notification shows. Threaded from the session, which knows the
  /// peer; the call itself only knows the room. The other two are the text
  /// the PLATFORM renders -- the notification's mute button and the name of
  /// its channel in system settings -- which the package cannot translate
  /// itself, so the app hands them over in the learner's language.
  String foregroundLabel = '';
  String foregroundMuteLabel = '';
  String foregroundChannelName = '';

  /// This call's claim on the ongoing-call service: the generation the
  /// platform issued when it started, carried back on every later
  /// instruction so none of them can land on the following call.
  int _foregroundGeneration = 0;

  /// Adds or removes the CAMERA type on the running service. Safe to call on
  /// any platform; a call without the service ignores it.
  Future<void> setForegroundCamera(bool on) async {
    final generation = _foregroundGeneration;
    if (generation == 0) return;
    try {
      await _foreground?.setCamera(on, generation: generation);
    } catch (e, s) {
      Logs().w('Could not update the call service camera type', e, s);
    }
  }

  /// Hands notification actions to whoever owns the call's controls.
  void foregroundActions(void Function(String action) handle) =>
      _actionEpoch = _foreground?.onAction(handle);

  /// Releases the action handler -- only the claim this call holds. The slot
  /// is process-global and last-writer-wins; a session held for its summary
  /// disposes AFTER the next call installed its handler, and clearing
  /// unconditionally would strip that call of its notification buttons.
  void clearForegroundActions() {
    final epoch = _actionEpoch;
    if (epoch != null) _foreground?.clearActionHandler(epoch);
    _actionEpoch = null;
  }

  Future<void> _startForeground({required bool video}) async {
    final foreground = _foreground;
    if (foreground == null) return;
    try {
      // The generation IS the claim: this call's ticket to instruct the
      // service later. Zero means the platform refused.
      final generation = await foreground.start(
        peer: foregroundLabel,
        video: video,
        muteLabel: foregroundMuteLabel,
        channelName: foregroundChannelName,
      );
      final started = generation != 0;
      _foregroundGeneration = generation;
      _foregroundClaimed = started;
      _foregroundPending = !started;
      // Reconciled after the step, exactly as the media connect does, and for
      // the same reason: this start was fired unawaited, so a hangup landing
      // while the platform was still answering cannot stop it. Teardown had
      // already read the claim as false and skipped the stop, and the service
      // -- ongoing notification and all -- outlived the call that started it.
      if (started && (_ending || _disposed)) {
        _foregroundClaimed = false;
        _foregroundPending = false;
        unawaited(
          _foreground?.stop(generation: generation).catchError((
            Object e,
            StackTrace s,
          ) {
            Logs().w('Could not stop the late call foreground service', e, s);
          }),
        );
      }
    } catch (e, s) {
      // The service is the call's survival in the background, never its
      // existence. A platform refusal costs that survival, not the call.
      Logs().w('Could not start the call foreground service', e, s);
    }
  }

  /// The platform saying the ongoing-call service never actually started.
  ///
  /// `start()` has to answer before Android runs the service's own start
  /// command -- that is what `startForegroundService` means -- so its success
  /// is "asked for", not "running". When the promotion is then refused the
  /// service stops itself, and without this the call went into the background
  /// believing it was protected by something that had already gone. Giving the
  /// claim back also re-arms the retry: the next moment the app is
  /// legitimately in the foreground, it asks again.
  void foregroundRefused() {
    if (!_foregroundClaimed && !_foregroundPending) return;
    Logs().w('The call foreground service refused to start; not protected');
    _foregroundClaimed = false;
    _foregroundPending = true;
    // And ASK AGAIN, here, rather than only at the one checkpoint after media
    // connects. A refusal is asynchronous -- the platform answers `start()`
    // before it runs the service -- so it can land at any moment of the call,
    // including long after that checkpoint has passed. Left to the checkpoint
    // alone, a call refused at second thirty went into the learner's pocket
    // believing it was protected by a service that had already stopped.
    //
    // Once, and only while the call is live and on screen: a refusal from the
    // background is Android saying no for a reason that will not have changed
    // by trying again immediately, and a retry loop is how a refusal becomes
    // a battery drain.
    if (_retriedForeground || _ending || _disposed) return;
    _retriedForeground = true;
    unawaited(_startForeground(video: _isVideoCall));
  }

  /// One retry per call, so a refusal cannot become a loop.
  bool _retriedForeground = false;

  /// Gates the recording to match the microphone button. Muting stops LiveKit
  /// publishing to the peer; this stops the recorder capturing too, which on
  /// Android it otherwise would — the tap there is upstream of the publish mute.
  void setMuted(bool muted) => capture.setMuted(muted);

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
    _wanted =
        elected &&
        _peerArrived &&
        (_roster?.hasPeer ?? false) &&
        !_peerMembershipGone &&
        // Never while their return is in doubt: presence during a grace may be
        // the SFU's echo of someone already gone, and audio recorded into that
        // is audio nobody heard.
        _peerGrace == null &&
        (_roster?.isConnected ?? false);
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
        Logs().i(
          _peerGrace != null
              ? 'Recording paused: waiting to see whether they come back'
              : 'Another device of this account is recording this call',
        );
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

  /// Talking time is SEGMENTS, not one start/end pair. The peer can drop and
  /// return within the grace window, and a single pair cannot say "paused
  /// across the gap": clearing the end swallows the gap into the total, and
  /// keeping it freezes the clock for good. Closed stretches accumulate here;
  /// [_segmentOpenedAt] is the one still running, if any.
  final List<Duration> _closedTalk = [];
  DateTime? _segmentOpenedAt;

  /// Counts the running segment into [_closedTalk]. Safe to call when none is
  /// open — ending a call that is already in the grace pause closes nothing.
  void _closeTalkSegment() {
    final from = _segmentOpenedAt;
    _segmentOpenedAt = null;
    if (from != null) _closedTalk.add(DateTime.now().difference(from));
  }

  /// The grace this call extends a vanished peer before concluding they are
  /// gone. Matched to LiveKit's departureTimeout default: that is how long the
  /// SFU actually keeps their place, and a "reconnecting" shown past the point
  /// return is possible would be a lie.
  static const peerGraceWindow = Duration(seconds: 20);

  /// How long the peer must STAY present before their return counts.
  ///
  /// The SFU holds a departed participant for its own departure timeout, and
  /// that retention can be re-reported to us -- on our own reconnect, or as a
  /// late update -- as though they were back. On a real device that echo
  /// cancelled the grace, and because nothing changed afterwards the call hung
  /// open for good: microphone live, membership heartbeating, nobody there. A
  /// return is believed only once it has survived this long, which is nothing
  /// against a twenty-second window.
  static const peerReturnConfirmed = Duration(seconds: 3);

  /// How close to their departure a membership retraction still counts as
  /// "they pressed end".
  ///
  /// A deliberate hangup retracts as it leaves, so the two arrive together. A
  /// device that merely vanished retracts nothing -- the SERVER eventually
  /// does it for them, when the delayed leave it registered runs out, and that
  /// late retraction is not a decision anyone made. The window separates the
  /// two without either side needing a new message.
  ///
  /// Thirteen seconds, and the number is derived rather than guessed. The app
  /// asks the homeserver to apply the delayed leave `CallDelayedLeave
  /// .applyLeave` after the last restart and restarts it every
  /// `CallDelayedLeave.maxRestart` at the slowest, so the EARLIEST a
  /// server-written retraction can appear is the difference between those two
  /// after a device stopped heartbeating. Anything sooner cannot be the
  /// server's, so this is as much room for slow delivery as can be taken
  /// without ever mistaking the server's cleanup for a decision -- and it
  /// stays inside [peerGraceWindow], so a genuine vanish is unaffected.
  ///
  /// Those two are the app's numbers, not the SDK's defaults, and they were
  /// raised together precisely so this one stayed true; call_timeouts_test.dart
  /// asserts the relation rather than leaving it to this comment. Raising the
  /// restart interval alone moves that retraction EARLIER and is what would
  /// break it.
  ///
  /// The original four seconds was chosen for how quickly a hangup normally
  /// arrives, not for what it had to be distinguished FROM, and any sync
  /// slower than that turned a hangup back into a vanish -- the fake
  /// "reconnecting" again, caused by the network this time rather than by
  /// the code.
  /// The residual, stated plainly: this is measured from when WE saw them
  /// leave the SFU, because nothing local can tell a retraction written at
  /// their departure and delivered late from one written late and delivered
  /// at once. A sync slower than this degrades to the ordinary grace, which
  /// is the behaviour we had before and costs at most seven more seconds.
  static const endedDeliberatelyWithin = Duration(seconds: 13);

  /// When the peer was first seen to be gone, or null while they are here.
  DateTime? _peerLeftAt;

  /// How often the call re-reads presence on its OWN clock.
  ///
  /// The state machine must never depend on an event that may not come. Roster
  /// notifications are welcome, but the truth is re-derived on this tick too --
  /// which is also what ends a call whose peer crashed without a leave event, a
  /// guarantee the tests asserted while production had only the SFU's events.
  static const presenceRecheck = Duration(seconds: 2);

  Timer? _peerGrace;

  /// When the peer was first seen again during a grace, null if not yet.
  DateTime? _peerBackSince;

  /// Who the peer is, learned from the roster while they were visibly here.
  /// Needed to ask the ROOM about them once the SFU stops being trustworthy.
  String? _peerUserId;

  /// Whether the SFU's claim that the peer is present can be believed.
  ///
  /// It cannot, on its own. The SFU keeps a departed participant for its
  /// departure timeout, and a reconnect of OUR connection re-lists them from
  /// that retention -- on a real phone the list then never dropped them
  /// again, so a call whose peer had hung up stayed open indefinitely, with
  /// a live microphone. Their Matrix membership is the authority in the
  /// other direction: leaving RETRACTS it, and a peer who has retracted is
  /// gone no matter who the SFU still lists. (A crash retracts nothing, so
  /// this filter stays quiet there and the roster remains in charge.)
  /// Whether their membership has ever been SEEN, so its absence means
  /// something. Strictly transition-based, the same rule the ringing banner
  /// states: room state can lag a join by seconds, and reading "not synced
  /// yet" as "left" would end calls that had only just begun.
  bool _peerMembershipSeen = false;

  bool get _peerMembershipGone {
    final room = _room;
    final peer = _peerUserId;
    if (room == null || peer == null) return false;
    switch (calls.peerPresenceInCurrentCall(
      room,
      peer,
      // Two floors, because the two answers are not symmetrical. Presence may
      // predate our join by a ring's lifetime -- whoever called us was here
      // first. A DEPARTURE may not: only a retraction written since we joined
      // can be a departure from this call.
      notBefore: _stateFloor(room),
      goneAfter: _ourJoinAt(room),
    )) {
      case PeerPresence.live:
        _peerMembershipSeen = true;
        return false;
      case PeerPresence.gone:
        // Only once we can date our OWN join. Until then there is no floor to
        // measure a departure against, and the newest thing the peer wrote is
        // the retraction that ended the LAST call -- which is seconds old on a
        // redial or a call back. Acting on it tore down calls two seconds
        // after they were answered, and it is the same rule as the floor
        // itself: presence may predate our join, a departure may not.
        if (_ourJoinAt(room) == null) return _peerMembershipSeen;
        // A retraction speaks for itself. Requiring that we had SEEN them live
        // first was the transition rule doing too much work: it exists so that
        // state which has not synced yet cannot read as a departure, and an
        // empty membership list is not unsynced state -- it is the departure,
        // written down. An answerer whose first sight of the caller's state is
        // the retraction was still sent into a 20-second grace by it.
        return true;
      case PeerPresence.unknown:
        return _peerMembershipSeen;
    }
  }

  /// The earliest a membership can have been written and still belong to THIS
  /// call, in server time.
  ///
  /// Our own membership is the anchor: nobody can have joined the call we are
  /// on more than one ring lifetime before we did, because the ring that
  /// invited us would have expired first. Anything older is a leftover of an
  /// earlier call -- and since the call id is the room id, a leftover is
  /// indistinguishable from a live membership without this.
  ///
  /// Null until our own membership has been written, which is the honest
  /// answer then: with no anchor there is nothing to measure staleness
  /// against, and the read falls back to expiry alone.
  /// When THIS device joined the call, in server time.
  DateTime? _ourJoinAt(matrix.Room room) {
    final anchor = _membershipEventId;
    if (anchor == null) return null;
    return _ourJoinAtValue ??= calls.membershipWrittenAt(room, anchor);
  }

  DateTime? _ourJoinAtValue;

  DateTime? _stateFloor(matrix.Room room) {
    final anchor = _membershipEventId;
    if (anchor == null) return null;
    final cached = _stateFloorAt;
    if (cached != null) return cached;
    final written = calls.membershipWrittenAt(room, anchor);
    if (written == null) return null;
    return _stateFloorAt = CallService.callFloorFrom(written);
  }

  DateTime? _stateFloorAt;

  Timer? _presenceClock;

  void _startPresenceClock() {
    _presenceClock?.cancel();
    _presenceClock = Timer.periodic(presenceRecheck, (_) {
      if (_ending || _disposed) return;
      // A call cannot outlive the room it is in. Leaving the chat -- from the
      // details pane, the menu, or another of this learner's devices -- goes
      // straight to the SDK and knows nothing about calls, so the media, the
      // recording and Android's foreground service all carried on afterwards
      // and the learner had to notice and hang up separately. Read on this
      // clock rather than through another subscription: the rule is the same
      // one the rest of this tick serves, that state is re-derived and never
      // waited for.
      final room = _room;
      if (room != null && room.membership != Membership.join) {
        Logs().i('The room this call is in is no longer joined; ending it');
        unawaited(hangUp());
        return;
      }
      _onParticipantsChanged();
    });
  }

  /// Whether the peer has vanished mid-call and is being waited for.
  bool get peerReconnecting => _peerGrace != null;

  /// The grace ran out with nobody back. The call HAPPENED — it was answered
  /// and talked on — so it ends as a call, not as a miss.
  void _peerGraceLapsed() {
    _peerGrace = null;
    if (_ending) return;
    Logs().i('The other participant did not return; ending the call');
    unawaited(hangUp());
  }

  /// Ages a pending return past its confirmation window and re-reads
  /// presence, as the call's own clock does a few seconds later.
  @visibleForTesting
  Future<void> confirmPeerReturnForTest() async {
    final since = _peerBackSince;
    if (since != null) {
      _peerBackSince = since.subtract(peerReturnConfirmed * 2);
    }
    _onParticipantsChanged();
    await _handover;
  }

  /// Fires the grace lapse now instead of after twenty real seconds, for the
  /// same reason [waitForPeerTimeoutForTest] exists.
  @visibleForTesting
  Future<void> peerGraceLapseForTest() async {
    final grace = _peerGrace;
    if (grace == null || !grace.isActive) return;
    grace.cancel();
    _peerGraceLapsed();
    await _hangUp;
  }

  bool get _peerArrived => _talkStartedAt != null;

  /// Notes that somebody is on the other end. Every route to that fact goes
  /// through here, so the moment is always recorded with it — and a talking
  /// segment is open from it, the first or one resumed after a grace pause.
  /// When the CALL began, as opposed to when this session did.
  ///
  /// The clock on screen counts from here, so a rejoined session carries on
  /// from where the call actually is instead of restarting at zero -- both
  /// people watching one call should read the same number. Distinct from
  /// [talkDuration], which is the segmented time anyone was actually able to
  /// hear, and is what the card and the analytics use.
  ///
  /// Stamped from THIS device's clock at the moment it first sees the other
  /// person, which leaves the two sides apart by however differently the SFU
  /// delivered that one roster change -- measured at well under a second, and
  /// self-correcting in that neither side's number drifts afterwards.
  /// Anchoring to the membership event's `origin_server_ts` instead was
  /// considered and rejected: it would make the two sides agree on the START
  /// but not on the ELAPSED time, because each still subtracts it from its own
  /// clock, so two devices whose clocks differ by a minute would read a minute
  /// apart -- trading a sub-second, bounded difference for an unbounded one.
  /// The rejoin path is the exception and uses the server timestamp anyway,
  /// because there the alternative is restarting at zero, which is worse than
  /// any skew.
  DateTime? get callStartedAt => _callStartedAt;

  DateTime? _callStartedAt;

  /// Who the other person is, learned at the same moment we learn that
  /// somebody IS there.
  ///
  /// These two facts have to travel together. The identity used to be derived
  /// only inside the roster-change handler, and an ANSWERER starts with the
  /// caller already in the roster -- so the first change it ever sees can be
  /// the caller LEAVING, with `rosterHasPeer` already false and the id never
  /// learned. Every read that needs to know whether the peer retracted then
  /// answers "no peer, no opinion", and a deliberate hangup went back to
  /// costing the answerer a 20-second grace.
  void _learnPeerIdentity() {
    if (_peerUserId != null) return;
    final me = calls.client.userID;
    for (final p in _roster?.participants ?? const {}) {
      if (p.userId != me && p.userId.isNotEmpty) {
        _peerUserId = p.userId;
        return;
      }
    }
  }

  void _notePeerPresent() {
    _learnPeerIdentity();
    _callStartedAt ??= DateTime.now();
    final firstArrival = _talkStartedAt == null;
    _talkStartedAt ??= DateTime.now();
    _segmentOpenedAt ??= DateTime.now();
    if (firstArrival) _dropBreadcrumb();
  }

  /// Leaves the reload trace once this is a conversation with an identity.
  ///
  /// Retried from the announce path because the first arrival can precede
  /// the membership echo; whichever lands second writes it.
  /// Whether this call asked for video, remembered for the breadcrumb.
  bool _isVideoCall = false;

  void _dropBreadcrumb() {
    final room = _room;
    final anchor = _membershipEventId;
    if (room == null || anchor == null || _ending) return;
    Logs().i('Leaving the call breadcrumb for ${room.id}');
    unawaited(
      CallBreadcrumb.drop(
        account: room.client.clientName,
        roomId: room.id,
        membershipEventId: anchor,
        // So a return brings the call back as what it was, camera and all.
        video: _isVideoCall,
      ),
    );
  }

  /// Notes that the talking is over. Called as the call starts to end rather
  /// than when it has finished ending.
  void _noteTalkEnded() {
    _talkEndedAt ??= DateTime.now();
    _closeTalkSegment();
  }

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

  /// How long a rejoin waits before concluding the call it re-entered is over.
  /// Bounded well inside the SFU's room retention: past that the peer cannot
  /// still be waiting for us anyway.
  static const _rejoinWithin = Duration(seconds: 5);

  bool _rejoining = false;

  /// Whether this session re-entered a call rather than starting one.
  bool get rejoinedCall => _rejoining;

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

  bool _wasRecovering = false;

  /// Whether the peer can currently be heard, per the roster's rule.
  bool get peerMuted => _roster?.peerMuted ?? false;

  bool _wasPeerMuted = false;

  void _onParticipantsChanged() {
    if (_ending) return;

    // The badge is presence-adjacent state: repaint on its transitions.
    final muted = _roster?.peerMuted ?? false;
    if (muted != _wasPeerMuted) {
      _wasPeerMuted = muted;
      if (!_disposed) notifyListeners();
    }

    // Surfaced, not merely tolerated. The roster already freezes its picture
    // while the connection recovers; the screen needs to SAY so, or the learner
    // watches a ticking timer over dead media.
    final recovering = _roster?.isRecovering ?? false;
    if (recovering != _wasRecovering) {
      _wasRecovering = recovering;
      if (!_disposed) notifyListeners();
    }

    // From the SFU, which is the only thing that knows who is actually here.
    // Matrix membership cannot answer this: it is room state on a multi-minute
    // expiry, so it lags a join by seconds and a crash by minutes. The roster
    // holds its last picture while the connection is down, so a reconnect —
    // which empties and refills the participant list — does not read as the
    // other person hanging up.
    final rosterHasPeer = _roster?.hasPeer ?? false;
    if (rosterHasPeer) _learnPeerIdentity();
    // A peer the room says has left is not here, whatever the SFU reports.
    final peerHere = rosterHasPeer && !_peerMembershipGone;
    if (peerHere && _peerGrace != null) {
      // Seen again mid-grace. NOT believed yet: the SFU re-reports a departed
      // participant inside its own retention window, and taking that echo for
      // a return cancelled the one bounded thing in this machine. The clock
      // brings us back to check.
      final backSince = _peerBackSince ??= DateTime.now();
      if (DateTime.now().difference(backSince) < peerReturnConfirmed) {
        _electRecorder();
        return;
      }
    }
    if (!peerHere) _peerBackSince = null;
    if (peerHere) {
      final firstArrival = !_peerArrived;
      final returned = _peerGrace != null;
      _peerGrace?.cancel();
      _peerGrace = null;
      _peerBackSince = null;
      _peerLeftAt = null;
      _notePeerPresent();
      _waitingForPeer?.cancel();
      _waitingForPeer = null;
      // The screen decides whether this was a real call from this, so it has to
      // hear about it — the stage does not change when someone answers, nor
      // when they make it back inside the grace.
      if ((firstArrival || returned) && !_disposed) notifyListeners();
      // Taken here as well, because this runs throughout the call while the
      // teardown read happens once. A membership whose echo was still on its
      // way at that single moment left a device with nothing to anchor its
      // analytics to, and every word its learner spoke was dropped.
      _rememberMembership();
    } else if (_peerArrived && (_roster?.isConnected ?? false)) {
      // They are not here, and our own connection is fine. WHY they went
      // decides everything, and there are only two answers.
      //
      // They pressed end. Their client retracts its membership as it goes, so
      // the retraction lands with the departure -- and a call the other
      // person deliberately ended is OVER. Showing "reconnecting" then is a
      // promise nobody is coming to keep.
      //
      // Or they vanished: a refresh, a crash, a network hole. Nothing
      // retracted, so their membership is still standing, and for the SFU's
      // departure window this really is "reconnecting" -- they can come back,
      // and the Return offer on their side exists to bring them.
      _peerLeftAt ??= DateTime.now();
      final leftDeliberately =
          _peerMembershipGone &&
          DateTime.now().difference(_peerLeftAt!) <= endedDeliberatelyWithin;
      if (leftDeliberately) {
        Logs().i('The other participant ended the call; ending it here too');
        unawaited(hangUp());
        return;
      }
      if (_peerGrace == null) {
        Logs().i('The other participant dropped; holding their place');
        _closeTalkSegment();
        _peerGrace = Timer(peerGraceWindow, _peerGraceLapsed);
        if (!_disposed) notifyListeners();
      }
    } else if (_peerArrived) {
      // Gone AND our own connection is gone for good — the roster only shows
      // an empty list disconnected once recovery is over. There is no one to
      // wait for and no session to wait in.
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
    // The third breadcrumb site, for the ordering the other two cannot
    // cover: an announce whose echo timed out returns null, and the anchor
    // only ever arrives HERE, later, from state -- with the peer long since
    // noted. The drop fires wherever the LAST of its two facts lands.
    if (_membershipEventId != null && _peerArrived) _dropBreadcrumb();
    _ringOnceTheAnchorArrives();
  }

  /// Watches for a membership whose echo was late, so the ring can still go.
  Timer? _lateRing;

  void _watchForALateAnchor() {
    _lateRing?.cancel();
    var tries = 0;
    _lateRing = Timer.periodic(const Duration(seconds: 2), (timer) {
      tries++;
      final room = _room;
      if (_ending || _disposed || _rangOut || room == null || tries > 8) {
        timer.cancel();
        _lateRing = null;
        return;
      }
      _membershipEventId ??= calls.membershipEventIdIn(room);
      if (_membershipEventId == null) return;
      timer.cancel();
      _lateRing = null;
      _ringOnceTheAnchorArrives();
    });
  }

  /// Runs the late-anchor check now, for tests.
  @visibleForTesting
  void lookForALateAnchorNow() {
    final room = _room;
    if (room == null) return;
    _membershipEventId ??= calls.membershipEventIdIn(room);
    _ringOnceTheAnchorArrives();
  }

  /// Rings the call that could not ring yet.
  ///
  /// The ring must name our membership, and the wait for that id is bounded
  /// so a caller is never left hanging -- but when the echo simply arrives
  /// late, the ring used to be skipped outright: the callee's phone never
  /// rang, no push went out, and the caller sat through the answer timeout
  /// for a call the other person was never told about. The id lands here,
  /// later, and this is where the ring catches up.
  void _ringOnceTheAnchorArrives() {
    if (!_placed || _ending || _disposed) return;
    if (_notificationId != null || _rangOut) return;
    final room = _room;
    final anchor = _membershipEventId;
    if (room == null || anchor == null) return;
    _rangOut = true;
    Logs().w('The membership arrived late; ringing now');
    unawaited(() async {
      try {
        _notificationId = await calls.ring(
          room,
          membershipEventId: anchor,
          video: _isVideoCall,
        );
        _catchUpOnDeclines();
      } catch (e, s) {
        Logs().w('Could not ring after the membership arrived', e, s);
      }
    }());
  }

  /// Declines seen before this call knew which notification was its own.
  ///
  /// The subscription is deliberately older than the id it matches, so a
  /// decline can arrive while the ring's own send is still returning. Dropping
  /// it would leave the caller sitting through the full ring having already
  /// been turned down.
  /// Kept with its REASON, not just its existence: a busy line that beat the
  /// ring's own send used to replay as an ordinary decline, so the caller was
  /// told they had been turned down when the truth was the other line was
  /// engaged -- no engaged tone, and the wrong line in their history.
  final Map<String, Object?> _declinedBefore = {};

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
      _declinedBefore[target] = event.content[CallService.declineReasonField];
      return;
    }
    if (target != ours) return;
    // A device that could not take the call said so with a reason; a person
    // turning it down sends none. Kept apart because the caller's screen and
    // their history should not read "they turned you down" when the truth is
    // that their line was busy.
    _noteDeclineReason(event.content[CallService.declineReasonField]);
    _onDeclined();
  }

  /// A device that could not take the call said so with a reason; a person
  /// turning it down sends none. Kept apart because the caller's screen and
  /// their history should not read "they turned you down" when the truth is
  /// that their line was busy.
  void _noteDeclineReason(Object? reason) {
    if (reason == CallService.declineBusy) _peerWasBusy = true;
  }

  /// Whether the decline came from a device already in another call.
  bool get peerWasBusy => _peerWasBusy;

  bool _peerWasBusy = false;

  /// Replays a decline that arrived before this call had an id to match it to.
  void _catchUpOnDeclines() {
    final ours = _notificationId;
    if (ours == null || !_declinedBefore.containsKey(ours)) return;
    _noteDeclineReason(_declinedBefore.remove(ours));
    _onDeclined();
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

  /// Set exactly once, at the moment the call's fate is decided — the user hung
  /// up, the peer declined or left, or coming up failed — and notified at that
  /// same moment. The UI closes (or shows the failure) off THIS, immediately,
  /// while teardown finishes behind it.
  CallOutcome? get outcome => _outcome;
  CallOutcome? _outcome;

  void _decide(CallOutcome o, [Object? error]) {
    if (_outcome != null) return;
    _outcome = o;
    if (error != null) _error = error;
    if (!_disposed) notifyListeners();
  }

  /// Whether the SFU connection is trying to come back mid-call. The roster
  /// freezes its participant picture while this is true, so a network blip can
  /// never read as the other person leaving; the screen shows it instead of a
  /// ticking timer over dead media.
  bool get isReconnecting => _roster?.isRecovering ?? false;

  /// When the conversation started, for the timer on screen. Null until
  /// somebody is on the other end — ringing is not talking.
  DateTime? get talkStartedAt => _talkStartedAt;

  /// How long the two sides were actually both on the call.
  ///
  /// Kept here rather than measured by the screen because this is what knows
  /// when they arrived and when the call began to end. The screen only sees
  /// stage changes, and the last of those lands after teardown — so measuring
  /// there charged the conversation for the flush and the upload that follow it.
  ///
  /// The sum of the closed segments plus the one still running. Time the peer
  /// spent vanished inside the grace window is nobody talking, and it is not
  /// counted — the card, the ticking timer and the summary all read this same
  /// sum, so no surface can disagree about how long the conversation was.
  Duration get talkDuration {
    var total = Duration.zero;
    for (final segment in _closedTalk) {
      total += segment;
    }
    final open = _segmentOpenedAt;
    if (open != null) total += DateTime.now().difference(open);
    return total;
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
  ///
  /// [rejoinAnchor] makes this a RE-ENTRY into a call this account was already
  /// on before a reload: the original membership event id, which stays the
  /// call's identity. A rejoin never rings, never announces a new call, and
  /// waits only briefly for the peer -- if the roster stays empty the call was
  /// over, and it leaves as quietly as it came.
  Future<void> start(
    matrix.Room room, {
    required bool video,
    bool answering = false,
    String? rejoinAnchor,
    DateTime? rejoinSince,
  }) => _starting = _start(
    room,
    video: video,
    answering: answering,
    rejoinAnchor: rejoinAnchor,
    rejoinSince: rejoinSince,
  );

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
    String? rejoinAnchor,
    DateTime? rejoinSince,
  }) async {
    _room = room;
    _isVideoCall = video;
    _rejoining = rejoinAnchor != null;
    _startedAt = DateTime.now();
    // At the EARLIEST guaranteed-foreground moment, strictly before the first
    // await: the app is on screen right now because the user just started or
    // answered this call, and Android's while-in-use rule for the microphone
    // service type is satisfied here and not necessarily later. When the
    // permission dialog is still up this returns unstarted, and the retry
    // below runs at the first moment that is by construction post-grant.
    //
    // NOT when the account is already in a call: the join below will refuse
    // this start, and the service is the LIVE call's -- a refused start that
    // touched it would overwrite that call's notification with this one's
    // name. The same busy check join performs, read early for the same
    // answer. (The service itself also ignores a START while running, which
    // covers the sub-millisecond double-start this read cannot see.)
    if (!calls.isBusy) unawaited(_startForeground(video: video));
    // Subscribed before anything else, but only when PLACING. Two people
    // calling at the same moment is decided by seeing the other's ring, and the
    // window this has to cover starts when ours does — not when our media
    // happens to be ready. Someone ANSWERING has no glare to detect: they did
    // not place a call, so the caller's own ring — which lands on this same
    // stream, inside the glare window of a quick answer — is not evidence the
    // peer "also placed". Listening for it there just set a flag on the wrong
    // side of the call.
    // A rejoin has no glare to detect either: the call already exists, and
    // the only ring this stream could carry for it is the original one's past.
    if (!answering && rejoinAnchor == null) {
      _peerRings = calls.ringsIn(room).listen(_onPeerRing);
    }
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
      if (_foregroundPending) {
        // Media connected, so the microphone permission is granted -- the
        // dialog that refused the first start has been answered.
        _foregroundPending = false;
        unawaited(_startForeground(video: video));
      }
      // Not when the camera never opened: the ongoing-call notification
      // would advertise a video call that is running on audio.
      if (video && !media.cameraFailed && _foreground != null) {
        // Camera site (a): a call STARTED with video opens its camera inside
        // connect, never through the toggle. Through the guarded seam, like
        // site (b): a platform refusal is a log line, never an unhandled
        // async error.
        unawaited(setForegroundCamera(true));
      }

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
      // And the call's own clock beside the roster's events, so no state can
      // be reached that only a missing event would have moved us out of.
      _startPresenceClock();

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
      // A rejoin is never placing, however empty the room looks by the time we
      // get back: the call it re-enters was already placed, and reading an
      // empty roster as "new call" here would ring the peer for their own
      // call's past.
      final placing =
          !answering && rejoinAnchor == null && roster.participants.isEmpty;
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
      final String? membershipId;
      if (rejoinAnchor != null) {
        // The call already has an identity: the membership this account wrote
        // when it first joined -- it is what offered the rejoin. Re-announcing
        // over a LIVE one would mint a new anchor for a call that already has
        // one, and every surface keyed on it would split.
        //
        // Unless that membership is no longer standing. A device that crashed
        // leaves the SERVER to retract it, and once that delayed leave fires
        // there is nothing of ours in the room's state at all: we would rejoin
        // the SFU publishing no membership, and the other side -- which now
        // reads an empty list as a departure, correctly -- would sit out its
        // grace and hang up on somebody who was right there. So the anchor is
        // reused only while it is real, and otherwise we announce ourselves
        // again. Nothing splits in that case: a session that died without
        // retracting never wrote a card to split from.
        // ALWAYS announced, even when the old membership is still standing.
        // Announcing is not just how the room learns we are here -- it is
        // what enters the RTC session, which owns the membership refresh and
        // the delayed leave the homeserver will apply if we stop
        // heartbeating. Reusing a standing membership skipped all of that:
        // the returning process published nothing and refreshed nothing,
        // while the DEAD process's delayed leave was still pending on the
        // server. Return worked, the two of them talked, and eighteen
        // seconds later the server retracted a membership nobody was renewing
        // and the other side hung up on a call that was live.
        //
        // The call keeps the identity it already had: the fresh membership is
        // who we are NOW, the anchor is which call this is.
        _rejoinAnchorId = rejoinAnchor;
        membershipId = _membershipEventId = await calls.announce();
        // The call's clock continues from when this device first joined it,
        // not from this moment: a rejoin is the same call, and restarting at
        // zero made the two sides disagree about how long they had been
        // talking.
        //
        // The breadcrumb's own timestamp first, because it was written by THIS
        // device's clock -- the same clock the timer subtracts from. The
        // membership's `origin_server_ts` is the server's, so a device two
        // minutes off the server read two minutes into a thirty-second call
        // while the other side still read thirty seconds. Server time is the
        // fallback, for an offer recovered from state with no breadcrumb
        // behind it, and now is the fallback to that.
        _callStartedAt =
            rejoinSince ?? calls.membershipWrittenAt(room, rejoinAnchor);
      } else {
        membershipId = _membershipEventId = await calls.announce();
      }
      _abandonIfEnding();
      if (_peerArrived) _dropBreadcrumb();

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
      // The echo can simply be late. Skipping the ring outright meant the
      // callee's phone never rang and the caller waited out the answer
      // timeout for a call nobody was told about; this keeps looking for the
      // id and rings the moment it lands.
      if (placing && membershipId == null) _watchForALateAnchor();
      if (placing && membershipId != null) {
        // Remembered as an ATTEMPT, separately from the id coming back. Both
        // send responses can time out while the event itself lands — their
        // phone rings — and keying "did this call matter" on holding the id
        // would then skip the record entirely: a call that rang somebody would
        // leave no missed-call card. The attempt is the truth the record needs;
        // the id is only for matching a decline.
        _rangOut = true;
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
        // an answer, which is what the longer wait is for. A rejoin waits the
        // shortest of all: the peer is either still on the call or the call is
        // over, and membership cannot say which -- the roster is the truth the
        // tap went in to read.
        final wait = rejoinAnchor != null
            ? _rejoinWithin
            : answering
            ? _joinWithin
            : _answerWithin;
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
      // The account is already in a call. The claim this start tried to take is
      // held by another call coming up, so nulling the attempt is what stops
      // teardown from giving it back on this call's behalf — that would cancel
      // the join that DOES hold it.
      //
      // But this start had already opened its own ring subscription, up at the
      // very top before it reached the join, and THAT is this call's to close.
      // Leaving it alive left a call that never began still listening — its
      // stage stuck at connecting for as long as the screen stayed open, later
      // rings still turning on peerAlsoPlaced. Failing it closes the screen and
      // the subscription with it; nothing else was opened yet, so there is
      // nothing else to unwind, and no _tearDown that might touch the claim.
      _joinAttempt = null;
      unawaited(_peerRings?.cancel());
      _peerRings = null;
      Logs().w('Cannot start a call; this account is already in one');
      // The outcome too, not only the stage: the session's failed state and
      // the start-guard's "dismiss a dead call" both key off the outcome, and
      // without it this refusal sat as a live-looking session that blocked
      // every later start until somebody hung up a call that never existed.
      _decide(CallOutcome.failed, const AlreadyInACall());
      _to(CallStage.failed, const AlreadyInACall());
    } catch (e, s) {
      if (_ending) {
        // Tearing down underneath a step in flight is what made it throw, so
        // this is the same abandonment arriving as somebody else's error.
        // Telling the user their call failed would be untrue.
        Logs().d('Call abandoned while coming up: $e');
        return _abandon();
      }
      Logs().e('Could not start the call', e, s);
      // Decided BEFORE teardown, error included, so the screen can show what
      // went wrong the moment it went wrong rather than after the unwind.
      _decide(CallOutcome.failed, e);
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
    // Decided NOW: a decline that led here was recorded before this call, so
    // the outcome is already the right one, and the screen may close at once.
    _decide(_declinedByPeer ? CallOutcome.declined : CallOutcome.ended);
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
  /// The order, and why it is this and not strict reverse:
  ///
  /// 1. The membership is REMEMBERED, so late audio can still be anchored to
  ///    this call once the session is gone.
  /// 2. Media release and the LOCAL recorder stop run side by side. Releasing
  ///    the media is what tells the peer we have gone — they read presence from
  ///    the SFU, not from the membership — so nothing in the recording teardown
  ///    may hold it up.
  /// 3. The membership is retracted. Nobody is waiting on it by now, and it is
  ///    the one step a later attempt can retry.
  /// 4. ONLY THEN is the recording settled. Everything it waits for is choreo
  ///    speech-to-text, and by this point that holds nothing the learner can
  ///    see: the call has already been given back, so the next call can be
  ///    placed and an incoming ring is no longer suppressed. Settling before
  ///    the retract is what used to keep this account reading as busy for as
  ///    long as a transcription took.
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
    // Where every teardown path converges, including failures -- pairing the
    // stop with the start in one owner is what makes a start with no stop
    // impossible. Only when this call CLAIMED the service: a start skipped
    // by the busy check belongs to no service, and stopping here anyway
    // would take down the live call's.
    if (_foregroundClaimed) {
      unawaited(
        _foreground?.stop(generation: _foregroundGeneration).catchError((
          Object e,
          StackTrace s,
        ) {
          Logs().w('Could not stop the call foreground service', e, s);
        }),
      );
    }
    // The clean teardown erases the reload trace; only a death that never
    // ran this line leaves it standing, which is exactly what makes it the
    // signal.
    //
    // A call that FAILED is not a clean teardown. A rejoin whose token, focus
    // or SFU connect missed tears down like any other failure -- and erasing
    // the crumb there threw away the learner's only way back to a call that
    // is still live, with the peer sitting in it waiting. Keeping it costs a
    // Return offer that may find an empty room and leave quietly; erasing it
    // costs the call.
    // Read from the OUTCOME, not the stage: the stage becomes failed after
    // this teardown, and the outcome is decided before it, precisely so the
    // screen can say what went wrong straight away.
    final crumbAccount = _room?.client.clientName;
    if (_outcome != CallOutcome.failed && crumbAccount != null) {
      unawaited(CallBreadcrumb.clear(crumbAccount));
    }
    unawaited(_declines?.cancel());
    _declines = null;
    unawaited(_peerRings?.cancel());
    _peerRings = null;
    _waitingForPeer?.cancel();
    _waitingForPeer = null;
    _lateRing?.cancel();
    _lateRing = null;
    _peerGrace?.cancel();
    _peerGrace = null;
    _presenceClock?.cancel();
    _presenceClock = null;
    // A decline waiting out its grace when teardown arrives still happened.
    // Only the WAIT is abandoned, not the fact — otherwise a decline landing in
    // the last moment before the call gives up on its own is written as nobody
    // answering, when somebody did answer: they said no.
    //
    // The CARD may already state plain "ended": it is written the instant the
    // outcome latches, which is before this line runs when the user's own
    // hangup overtakes the decline's grace. Accepted: the window is under
    // 1.5s, both things genuinely happened, and preferring the hangup the
    // user themselves performed is at least as true as the decline.
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

    // Cleared unconditionally, whatever [_capturing] says. A device displaced
    // moments before the hangup has a stop still unwinding while [_capturing] is
    // already false, so acting only when it is true would leave that stretch
    // believing it was still wanted.
    _wanted = false;

    // The peer stops hearing us HERE, and NOTHING in the recording teardown may
    // hold it up — not the election handover, not the tap detach, not the
    // uploads. Their client reads who is present from the SFU, so leaving it
    // (media.dispose) is what tells them we have gone; the membership below is
    // bookkeeping they never look at. Two earlier orderings both left them
    // hearing a learner who had hung up: retracting before this, for the length
    // of a state write; and awaiting the recorder handover before this, for the
    // length of a reconcile that had stalled on a platform call. So it goes
    // first now, and alongside — not behind — everything the recording does.
    final releasingMedia = () async {
      try {
        await media.dispose();
      } catch (e, s) {
        Logs().e('Could not release the call media', e, s);
      }
    }();

    // The retraction goes out ALONGSIDE the media release, not behind the
    // recorder teardown. It is not bookkeeping any more: it is the only thing
    // that tells the other side this was a HANGUP and not a crash, and they
    // decide that within seconds of seeing us leave the SFU. Behind a tap
    // detach that is allowed five seconds, the retraction could arrive after
    // they had already given up and started waiting for us to come back --
    // the exact fake "reconnecting" this branch exists to remove. It still
    // does not go BEFORE the media release, because that ordering left them
    // hearing a learner who had already hung up.
    //
    // The anchor is read first: once the retraction lands, the membership can
    // no longer be matched to this call.
    _rememberMembership();
    unawaited(
      _releaseCall().catchError((Object e, StackTrace s) {
        Logs().w('Could not give the call back', e, s);
      }),
    );

    // The recorder teardown, running WITH the media release rather than before
    // it. The tap comes off and the chunker's buffered audio — which lives in
    // the capture service, not the LiveKit room, so the media release does not
    // take it — is flushed.
    //
    // The handover is NOT drained here. It is only given an error handler above
    // and awaited by nobody: a reconcile already inside a settling stop would
    // otherwise put choreo back on the critical path, which is the whole thing
    // this ordering exists to avoid. Nothing can restart recording once stop()
    // has bumped the capture session, and a flush still running is still
    // awaited — by finish(), whose stop joins the same in-flight one.
    //
    // Caught inside the closure, not left on a bare future: it can complete with
    // an error while the media release is being awaited, and a future with no
    // handler in that window surfaces as an unhandled async error.
    // Attached HERE, before any await below. The handover is no longer drained
    // on the critical path, and a future that completes with an error while
    // nothing is awaiting it surfaces as an unhandled async error.
    final drainingHandover = _handover.then<void>(
      (_) {},
      onError: (Object e, StackTrace s) {
        Logs().w('The recorder handover did not settle', e, s);
      },
    );

    final stoppingRecorder = () async {
      // stop() FIRST, before draining the handover. A reconcile's capture.start
      // still in flight — this device was elected to record at the very moment
      // of the hangup — would otherwise keep the recorder running and accepting
      // post-hangup frames until it finished, because the handover awaits that
      // start. stop() sets the no-more-frames gate at once and bumps the capture
      // session, so that start releases its tap when it lands. Draining the
      // handover afterwards lets it settle; nothing can restart it, _wanted is
      // already false.
      try {
        // WITHOUT settling the deliveries. They go to choreo, and a call is
        // over when the microphone and the membership are released, never when
        // a transcription answers. capture.finish() below waits for the very
        // same chunks with a far longer bound, so nothing is abandoned.
        await capture.stop(settleDeliveries: false);
      } catch (e, s) {
        Logs().e('Could not flush the call recording', e, s);
      }
    }();

    await releasingMedia;
    await stoppingRecorder;
    _capturing = false;

    // One more look before the session goes. The echo can land at any point
    // during teardown, and after the retract the membership can no longer be
    // matched to this call — which is exactly when a device that joined one
    // already under way has nothing else to anchor its learner's words to.
    _rememberMembership();

    // The membership last. Nobody is waiting on it — the peer already saw us
    // leave — and it is the one step that can be retried later if the server
    // refuses, so it costs nothing to do it once the devices are free.
    await _releaseCall();

    // Drained, never awaited, and only now that the call has been given back.
    // Nothing can restart recording by this point -- _wanted is false and the
    // stop above bumped the capture session -- so this is pure cleanup, and a
    // capture.start() that hung would otherwise hold the transcripts, and the
    // analytics credited from them, behind it for as long as it hung.
    unawaited(drainingHandover);

    // Last, with the devices and the membership already released: tell the
    // recording the call is over and let what is in flight land. This is the
    // ONLY wait on choreo in the whole teardown, and by now it holds nothing
    // the learner can see -- the call has already been given back, so the next
    // call can be placed and an incoming ring is no longer suppressed.
    try {
      await capture.finish();
    } catch (e, s) {
      Logs().e('Could not settle the call recording', e, s);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // The session that installed the action handler clears it in its own
    // dispose; cleared here TOO so the invariant is local -- a disposed call
    // leaves no process-global closure behind, whoever owned it.
    clearForegroundActions();
    unawaited(hangUp());
    super.dispose();
  }
}
