import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix show Event, Room, User;
import 'package:matrix/matrix.dart' show Logs;
import 'package:permission_handler/permission_handler.dart';

import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/calls/ring_player.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

import 'package:pangea_call_capture/pangea_call_capture.dart'
    show CallForegroundControl;

/// One call, owned ABOVE the widget tree.
///
/// A call is not a screen. The user minimizes it, reads other chats, comes
/// back — and the earlier design, where a page owned the call and disposing
/// the page hung it up, made that impossible by construction. This object owns
/// the call's lifecycle; panels and tiles are just views of it, free to mount
/// and unmount without touching the call.
///
/// Everything the recording needs is captured at construction — the room, the
/// ids, the languages, the analytics callback — so the record is written even
/// if every widget is long gone by the time the last chunk lands.
class CallSession extends ChangeNotifier {
  final matrix.Room room;

  /// Whether the call was asked for with video. What the timeline records is
  /// [usedVideo] — what actually happened — not this.
  final bool videoRequested;

  /// The ring this device answered, when answering. Null when placing.
  final String? notificationEventId;

  /// Tests hand in a player with a fake sound; the app builds the real one.
  final RingPlayer? tonesOverride;

  /// The CALLER's membership event id, carried by the ring this device
  /// answered. Null when placing (the caller's own echo stands in) and null
  /// on sessions that never saw a ring.
  final String? callerMembershipEventId;

  final CallMedia media;
  final ActiveCall call;
  final CallRecord _record;

  final String? _myUserId;
  final String? _peerUserId;

  bool _muted = false;
  bool _camera = false;
  bool _usedVideo = false;
  bool _reachedCall = false;
  bool _minimized = false;
  bool _over = false;
  bool _recordingFinished = false;

  /// How many widgets are currently SHOWING this call — the in-chat panel or
  /// tile registers itself while mounted for the call's room. When nobody is
  /// presenting, the global floating tile takes over, so the call is always
  /// reachable wherever the user has navigated.
  int _presenters = 0;

  Timer? _tick;

  /// Fires when the session is over and should be released by its holder.
  final void Function(CallSession) _onReleased;

  CallSession._({
    required this.room,
    required this.videoRequested,
    required this.notificationEventId,
    required this.media,
    required this.call,
    required CallRecord record,
    required String? myUserId,
    required String? peerUserId,
    required void Function(CallSession) onReleased,
    String? rejoinAnchor,
    DateTime? rejoinSince,
    this.callerMembershipEventId,
    this.tonesOverride,
  }) : _record = record,
       _myUserId = myUserId,
       _peerUserId = peerUserId,
       _onReleased = onReleased {
    _camera = videoRequested;
    // What the ongoing-call notification says. The call only knows the room;
    // the session knows who the conversation is with.
    call.foregroundLabel =
        peer?.calcDisplayname() ?? room.getLocalizedDisplayname();
    // The notification's buttons act on THIS session, through the same
    // controls the screen uses -- one mute path, one hangup path.
    _foregroundActions();
    // Android 13+ shows no notification without this. Asked at call start --
    // the moment its value is self-evident -- and a refusal costs only the
    // visible chip: the foreground service, which is the actual survival
    // mechanism, runs either way.
    if (!kIsWeb && Platform.isAndroid) {
      unawaited(
        Permission.notification.request().catchError((Object e) {
          Logs().w('Could not ask for the notification permission: $e');
          return PermissionStatus.denied;
        }),
      );
    }
    call.addListener(_onCallChanged);
    call.start(
      room,
      video: videoRequested,
      // Being rung is what makes this an answer. Derived from the room it
      // would be wrong exactly when the caller had already given up.
      answering: notificationEventId != null,
      rejoinAnchor: rejoinAnchor,
      rejoinSince: rejoinSince,
    );
  }

  /// Builds a session with every dependency the call and its record need,
  /// captured NOW. Nothing is read from a BuildContext later, because there is
  /// no widget whose lifetime this depends on.
  factory CallSession.start({
    required matrix.Room room,
    required bool video,
    required CallService callService,
    required ChunkTranscriber transcribe,
    required String userL1,
    required String userL2,
    required CallAnalyticsSink analytics,
    required void Function(CallSession) onReleased,
    String? notificationEventId,
    String? rejoinAnchor,
    DateTime? rejoinSince,
    String? callerMembershipEventId,
    @visibleForTesting RingPlayer? tonesOverride,
    @visibleForTesting CallMedia? mediaOverride,
    @visibleForTesting CallCaptureService? captureOverride,
    @visibleForTesting CallForegroundControl? foregroundOverride,
    @visibleForTesting CallRecord? recordOverride,
  }) {
    final media = mediaOverride ?? CallMedia();
    final transcripts = CallTranscriptSink(
      transcribe: transcribe,
      userL1: userL1,
      userL2: userL2,
    );
    final record =
        recordOverride ??
        CallRecord(
          roomId: room.id,
          transcripts: transcripts,
          sendEvent: (content, txid) =>
              room.sendEvent(content, type: PangeaEventTypes.call, txid: txid),
          analytics: analytics,
        );
    return CallSession._(
      room: room,
      videoRequested: video,
      notificationEventId: notificationEventId,
      media: media,
      call: ActiveCall(
        calls: callService,
        media: media,
        capture: captureOverride ?? CallCaptureService(sink: transcripts),
        // Android's background survival; every other platform passes null
        // and the call behaves exactly as before.
        foreground:
            foregroundOverride ??
            (!kIsWeb && Platform.isAndroid
                ? const CallForegroundControl()
                : null),
      ),
      record: record,
      myUserId: callService.client.userID,
      peerUserId: room.directChatMatrixID,
      onReleased: onReleased,
      rejoinAnchor: rejoinAnchor,
      rejoinSince: rejoinSince,
      callerMembershipEventId: callerMembershipEventId,
      tonesOverride: tonesOverride,
    );
  }

  // ---------------------------------------------------------------- state

  bool get minimized => _minimized;

  /// Whether the call is showing over the whole app rather than inside its
  /// chat pane. A choice, not the default: the pane is where the call lives,
  /// and this is the "make it big" button every video product offers.
  bool get fullscreen => _fullscreen;
  bool _fullscreen = false;

  void toggleFullscreen() {
    _fullscreen = !_fullscreen;
    if (_fullscreen) _minimized = false;
    _notify();
  }

  bool get muted => _muted;
  bool get cameraOn => _camera;
  bool get isOver => _over;
  bool get hasPresenter => _presenters > 0;

  /// The failure to show, when the call could not be established. The session
  /// stays alive in this state — a screen that vanishes on failure is
  /// indistinguishable from a crash — until [dismissFailed].
  bool get isFailed => call.outcome == CallOutcome.failed;

  CallStage get stage => call.stage;
  Object? get error => call.error;
  bool get isReconnecting => call.isReconnecting;
  bool get peerReconnecting => call.peerReconnecting;
  bool get peerMuted => call.peerMuted;
  bool get peerWasBusy => call.peerWasBusy;
  bool get hadPeer => call.hadPeer;
  bool get placedCall => call.placedCall;
  DateTime? get talkStartedAt => call.talkStartedAt;
  DateTime? get callStartedAt => call.callStartedAt;
  Duration get talkDuration => call.talkDuration;

  /// The other person in this direct message, for the name and face on screen.
  matrix.User? get peer {
    final id = _peerUserId;
    if (id == null) return null;
    return room.unsafeGetUserFromMemoryOrFallback(id);
  }

  /// Every published video track, ours and theirs. Latches [usedVideo] on the
  /// way past: nothing can appear on screen without coming through here, so
  /// this is the one read that cannot miss a remote camera coming on.
  List<lk.VideoTrack> videoTracks() {
    final tracks = <lk.VideoTrack>[
      ...media.room.remoteParticipants.values
          .expand((p) => p.videoTrackPublications)
          .map((p) => p.track)
          .whereType<lk.VideoTrack>(),
      ...?media.room.localParticipant?.videoTrackPublications
          .map((p) => p.track)
          .whereType<lk.VideoTrack>(),
    ];
    if (tracks.isNotEmpty) _usedVideo = true;
    return tracks;
  }

  // ---------------------------------------------------------------- actions

  void minimize() {
    if (_minimized && !_fullscreen) return;
    _minimized = true;
    // Minimizing IS leaving fullscreen; the tile takes over either way.
    _fullscreen = false;
    _notify();
  }

  void expand() {
    if (!_minimized) return;
    _minimized = false;
    _notify();
  }

  /// A view of this call for [room] came on screen (the in-chat panel/tile).
  void attachPresenter() {
    _presenters++;
    _notify();
  }

  void detachPresenter() {
    _presenters--;
    _notify();
  }

  /// The caller-side tones. Separate from the banner's ringtone: that one
  /// belongs to whoever is being called, this one to whoever is calling.
  late final RingPlayer _tones = tonesOverride ?? RingPlayer();

  bool _busyToned = false;

  /// Routes the ongoing-call notification's buttons into this session,
  /// through the SAME paths the on-screen buttons use -- one mute, one
  /// hangup, wherever they come from.
  void _foregroundActions() {
    call.foregroundActions((action) {
      Logs().i('Call notification action: $action');
      if (_disposing || _over) return;
      switch (action) {
        case 'hangup':
          endCall();
        case 'mute':
          unawaited(toggleMute());
      }
    });
  }

  Future<void> toggleMute() async {
    final next = !_muted;
    // The recorder gate goes up BEFORE muting and comes down only AFTER an
    // unmute has taken — never while the microphone is still muted. On Android
    // the recorder tap runs upstream of LiveKit's publish mute, so without its
    // own gate a muted learner would still be recorded.
    if (next) call.setMuted(true);
    try {
      await media.setMicrophoneEnabled(!next);
    } catch (e, s) {
      // Fail closed: a mute that did not take must ungate again (the mic is
      // still live); an unmute that did not take leaves the gate up.
      if (next) call.setMuted(false);
      Logs().w('Could not ${next ? 'mute' : 'unmute'} the call', e, s);
      return;
    }
    if (!next) call.setMuted(false);
    if (_disposing || _over) return;
    _muted = next;
    _notify();
  }

  Future<void> toggleCamera() async {
    final next = !_camera;
    try {
      await media.setCameraEnabled(next);
    } catch (e, s) {
      Logs().w('Could not turn the camera ${next ? 'on' : 'off'}', e, s);
      return;
    }
    // Camera site (b): the toggle, both directions, only after the change
    // actually took. Site (a) -- a call STARTED with video -- lives where the
    // camera opens, inside the call's own connect step.
    unawaited(call.setForegroundCamera(next));
    // Only if the camera actually came on: turning it on the instant the call
    // ends is a refused no-op that does not throw, and latching on the request
    // alone wrote an ending voice call as a video call. The live connection is
    // the proof it took.
    if (next && media.isConnected) _usedVideo = true;
    if (_disposing || _over) return;
    _camera = next;
    _notify();
  }

  /// Ends the call from a button. The UI is released AT ONCE — the outcome
  /// latch inside [ActiveCall.hangUp] fires immediately — while teardown, the
  /// last upload and the record run on behind it.
  void endCall() {
    _finishRecording();
    // The outcome notification from hangUp (via _finishRecording) drives
    // _onCallChanged, which releases the session.
  }

  /// Clears a failed call the user has read. The record still runs — a call
  /// whose ring went out is a missed call even if our side then failed.
  void dismissFailed() {
    _finishRecording();
    _release();
  }

  // ---------------------------------------------------------------- internals

  /// Latches "this was a video call" from the ROOM, not from a view. The
  /// panel's read covers the visible case; this covers a camera coming on
  /// while the call is minimized or floating, where no view asks for tracks.
  void _latchVideo() {
    if (_usedVideo) return;
    final room = media.room;
    final any =
        (room.localParticipant?.videoTrackPublications.isNotEmpty ?? false) ||
        room.remoteParticipants.values.any(
          (p) => p.videoTrackPublications.isNotEmpty,
        );
    if (any) _usedVideo = true;
  }

  void _onCallChanged() {
    _latchVideo();
    // The button reflects the camera the user HAS, not the one they asked
    // for. A video call whose camera was refused -- by a browser policy, or
    // by the user answering no to the prompt -- comes up on audio, and
    // leaving the control switched on meant the first press turned OFF a
    // camera that had never come on.
    if (_camera && media.cameraFailed) _camera = false;
    // The outcome is latched the instant the call's fate is decided, seconds
    // before the stage catches up — this is what makes hanging up feel
    // immediate on both sides.
    final outcome = call.outcome;
    if (outcome == CallOutcome.declined && call.peerWasBusy && !_busyToned) {
      // Once, and only for a line that was busy: the engaged tone is the
      // half of "they are on another call" that reaches someone who is not
      // looking at the screen.
      _busyToned = true;
      _tones.busy();
    }
    if (outcome == CallOutcome.ended || outcome == CallOutcome.declined) {
      // The card FIRST and immediately: everything it states is known now, and
      // it must not wait for teardown and transcription behind it.
      _writeCard();
      _finishRecording();
      // An ended conversation earns a moment on screen; everything else --
      // declined, missed, torn down unanswered -- goes at once, as it always
      // did. Teardown itself is never held by any of this.
      if (outcome == CallOutcome.ended && call.hadPeer) {
        _finishWithSummary();
      } else {
        _release();
      }
      return;
    }
    if (call.stage == CallStage.connected) _reachedCall = true;
    if (call.hadPeer && _tick == null && !_over) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        _latchVideo();
        if (!_over) _notify();
      });
    }
    if (!_over) _notify();
  }

  /// Whether this call is worth a timeline entry at all: did it reach the SFU,
  /// did it actually ring somebody, or was it itself an answer. A call that
  /// rang nobody and connected to nothing leaves no trace, correctly.
  bool get _mattered =>
      _reachedCall ||
      call.hadPeer ||
      call.rangOut ||
      notificationEventId != null;

  /// Puts the call in the timeline the moment it ends — not after teardown,
  /// and not after speech-to-text.
  bool _cardStarted = false;

  void _writeCard() {
    if (_cardStarted || !_mattered) return;
    _cardStarted = true;
    final identity = _callIdentity;
    unawaited(
      _record
          .writeCard(
            duration: call.talkDuration,
            video: _usedVideo,
            answered: call.hadPeer,
            declined: call.wasDeclined,
            writeTimelineEvent: _writesTheCall,
            callerId: identity.caller,
            callKey: identity.key,
            anchorEventId: notificationEventId ?? call.membershipEventId,
          )
          .catchError((Object e, StackTrace s) {
            Logs().e('Could not put the call in the timeline', e, s);
          }),
    );
    _scheduleSurvivorCheck(identity);
  }

  /// How long the survivor waits for the writer's card to arrive before
  /// concluding the writer died with it. Long enough for an ordinary write and
  /// a slow sync; the cost of waiting is only how late a rare recovered card
  /// appears.
  static const _survivorSettle = Duration(seconds: 15);

  /// Writes the card the WRITER never did.
  ///
  /// A call answered and talked on, whose writer died before its hangup wrote
  /// the card (a crashed browser, a killed tab), left no trace at all in the
  /// conversation. The surviving non-writer waits out the settle, re-reads
  /// the timeline, and writes a card carrying only what THIS side observed --
  /// but only for calls it saw ANSWERED (a survivor can never fabricate a
  /// missed/declined outcome), only with a ring- or glare-provenanced key (a
  /// rejoined session's anchor may be its own membership, the wrong key), and
  /// stamped with the same shared key so the renderer collapses the rare race
  /// where both raced to write.
  ///
  /// ACCEPTED GAP, stated not hidden: if BOTH sides reload and rejoin, both
  /// sessions are provenance-blind and neither writes -- that call leaves no
  /// card. A rejoiner cannot know post-reload whether it originally placed,
  /// and guessing writes a card under the wrong key, which is worse than a
  /// missing one. The server-side reconciler (filed follow-up) is the real
  /// answer for double-crash shapes.
  /// What the survivor timer will check, kept so a test can run the check
  /// without waiting out the settle.
  ({String key, String? caller})? _survivorPending;

  /// Runs the scheduled survivor check now instead of after the settle.
  /// Fifteen seconds of real time in a test proves nothing the check's own
  /// logic does not.
  @visibleForTesting
  Future<void> survivorCheckNowForTest() async {
    final pending = _survivorPending;
    if (pending == null) return;
    await _survivorCheck(pending.key, pending.caller);
  }

  void _scheduleSurvivorCheck(({String? key, String? caller}) identity) {
    final key = identity.key;
    if (_writesTheCall || !call.hadPeer || call.rejoinedCall || key == null) {
      return;
    }
    _survivorPending = (key: key, caller: identity.caller);
    Timer(_survivorSettle, () {
      unawaited(
        _survivorCheck(key, identity.caller).catchError((
          Object e,
          StackTrace s,
        ) {
          Logs().w('The survivor card check failed', e, s);
        }),
      );
    });
  }

  /// The room's current timeline events, as one read. A seam because the
  /// SDK's Timeline cannot be constructed outside it, and the survivor rule
  /// -- check, then write -- deserves tests that do not depend on the fake
  /// server's paging.
  @visibleForTesting
  Future<List<matrix.Event>> Function()? timelineEventsOverride;

  Future<List<matrix.Event>> _timelineEvents() async {
    final override = timelineEventsOverride;
    if (override != null) return override();
    final timeline = await room.getTimeline();
    try {
      return List.of(timeline.events);
    } finally {
      timeline.cancelSubscriptions();
    }
  }

  Future<void> _survivorCheck(String key, String? caller) async {
    final events = await _timelineEvents();
    final already = events.any(
      (e) =>
          e.type == PangeaEventTypes.call &&
          e.content[CallRecord.callKeyField] == key,
    );
    if (already) return;
    Logs().i('No card arrived for this call; the survivor writes it');
    await _record.writeSurvivorCard(
      duration: call.talkDuration,
      video: _usedVideo,
      callKey: key,
      callerId: caller,
    );
  }

  /// Ends the call, then writes it and its analytics. Every way out goes
  /// through here; `hangUp` is idempotent and memoised, so all callers join one
  /// teardown and the record is written once. Deliberately not awaited and not
  /// tied to any widget — it outlives everything visual.
  void _finishRecording() {
    if (_recordingFinished) return;
    _recordingFinished = true;
    unawaited(
      call
          .hangUp()
          .whenComplete(() async {
            try {
              await call.settled;
            } catch (_) {}
            // Written when the call either got established, actually rang the
            // other side, or was itself an answer. Placing alone is not enough:
            // a call whose announce failed rang nobody, and a card for it would
            // record a call that never began.
            if (!_mattered) return;
            // The card is normally already in the timeline by now (written the
            // moment the call ended); this call credits the transcripts against
            // it, and writes the card itself only if that earlier attempt had
            // failed outright.

            final identity = _callIdentity;
            return _record.finish(
              duration: call.talkDuration,
              video: _usedVideo,
              answered: call.hadPeer,
              declined: call.wasDeclined,
              writeTimelineEvent: _writesTheCall,
              callerId: identity.caller,
              callKey: identity.key,
              anchorEventId: notificationEventId ?? call.membershipEventId,
            );
          })
          .catchError((Object e, StackTrace s) {
            Logs().e('Could not finish the call recording', e, s);
          }),
    );
  }

  /// The call's shared identity and the caller its card names.
  ///
  /// ONE resolver for every writer -- fast path, finish, survivor -- so no
  /// two of them can disagree. The key is the CALLER's membership event id:
  /// the caller holds it as its own echo, the callee from the ring it
  /// answered, and on glare the tie-break winner's id is the key -- the loser
  /// learned it from the winner's simultaneous ring. The caller field names
  /// the same tie-break winner; `placedCall ? me : peer` would, on glare,
  /// name the LOSER on the loser's card.
  ({String? key, String? caller}) get _callIdentity => resolveCallIdentity(
    placed: call.placedCall,
    peerAlsoPlaced: call.peerAlsoPlaced,
    myUserId: _myUserId,
    peerUserId: _peerUserId ?? call.peerRingSenderId,
    ownMembershipId: call.membershipEventId,
    peerRingMembershipId: call.peerRingMembershipId,
    callerMembershipEventId: callerMembershipEventId,
  );

  /// The rule itself, pure so the glare arms can be pinned directly.
  @visibleForTesting
  static ({String? key, String? caller}) resolveCallIdentity({
    required bool placed,
    required bool peerAlsoPlaced,
    required String? myUserId,
    required String? peerUserId,
    required String? ownMembershipId,
    required String? peerRingMembershipId,
    required String? callerMembershipEventId,
  }) {
    // peerAlsoPlaced with placed=false is the SUB-MILLISECOND glare: each
    // side saw the other already in the SFU before deciding, so each derived
    // itself a joiner -- and each also saw the other's simultaneous ring,
    // which is the only way this flag turns on without placing. Neither is a
    // fast-path writer then, so without a key here the call went missing
    // from the conversation entirely; with the same tie-break as the placed
    // glare, both sides share a key and the SURVIVOR path writes the card.
    if (!placed && !peerAlsoPlaced) {
      return (key: callerMembershipEventId, caller: peerUserId);
    }
    if (placed && !peerAlsoPlaced) {
      return (key: ownMembershipId, caller: myUserId);
    }
    if (myUserId == null || peerUserId == null) {
      return placed
          ? (key: ownMembershipId, caller: myUserId)
          : (key: callerMembershipEventId, caller: peerUserId);
    }
    return myUserId.compareTo(peerUserId) < 0
        ? (key: ownMembershipId, caller: myUserId)
        : (key: peerRingMembershipId, caller: peerUserId);
  }

  /// Whether this device writes the call to the room. The placer writes it;
  /// simultaneous placers are settled by comparing ids.
  bool get _writesTheCall {
    if (!call.placedCall) return false;
    if (!call.peerAlsoPlaced) return true;
    final me = _myUserId;
    final peer = _peerUserId ?? call.peerRingSenderId;
    if (me == null || peer == null) return true;
    return me.compareTo(peer) < 0;
  }

  /// When the summary screen dismisses itself.
  static const summaryLifetime = Duration(seconds: 3);

  /// When the call ended, for the summary. Null until it has.
  DateTime? get endedAt => _endedAt;
  DateTime? _endedAt;

  /// Whether the summary screen is on: the call is over and its handover to
  /// the holder is being held while the learner reads what happened.
  bool get showingSummary => _over && !_handedOver && _summaryHold != null;

  bool _handedOver = false;
  Timer? _summaryHold;

  void _release() {
    _finish();
    _handover();
  }

  /// Latches the end. From here [isOver] is true, so the busy-claim is free
  /// and a new call steps over this session; only the visual handover waits.
  void _finish() {
    if (_over) return;
    _over = true;
    _endedAt = DateTime.now();
    _tick?.cancel();
    _tick = null;
    _notify();
  }

  /// Hands the finished session to the holder.
  ///
  /// Deferred a microtask always: this can run FROM the call's own listener
  /// walk (outcome -> _onCallChanged -> here), and the holder's release
  /// disposes the call -- disposing a notifier while it is still walking its
  /// listener list corrupts its bookkeeping, and the wreckage surfaces later
  /// as a RangeError inside notifyListeners. The same rule the roster
  /// teardown in _unwind already states.
  void _handover() {
    if (_handedOver) return;
    _handedOver = true;
    _summaryHold?.cancel();
    _summaryHold = null;
    scheduleMicrotask(() => _onReleased(this));
  }

  /// Ends the session but keeps the screen for a moment: avatar, name, "call
  /// ended", how long it was. Only for a call that WAS a conversation --
  /// [ActiveCall.hadPeer], the code's real somebody-was-here latch, never the
  /// stage, which reads connected while still waiting for an answer.
  /// Declined, failed and missed calls release at once, exactly as before.
  void _finishWithSummary() {
    if (_over) return;
    _finish();
    _summaryHold = Timer(summaryLifetime, _handover);
    _notify();
  }

  /// The X on the summary. Also the path a redial takes: startCall steps over
  /// an isOver session, and its replacement of the holder's value releases
  /// this one through [dispose], which converges on [_handover].
  void dismissSummary() => _handover();

  bool _disposing = false;

  /// Every notification goes through here. Async work — a device toggle, a
  /// late tick, a view detaching during teardown — can resume after the holder
  /// has disposed this session, and notifying a disposed ChangeNotifier is a
  /// crash. Late work is silently absorbed instead.
  void _notify() {
    if (_disposing) return;
    notifyListeners();
  }

  @override
  void dispose() {
    // Re-entrant by construction without this guard: disposing finishes the
    // recording, finishing hangs up, hanging up notifies, the listener releases
    // the session, and the holder's release callback disposes it AGAIN. The
    // listener comes off FIRST so the cascade cannot start, and the guard stops
    // a second disposal that is already on its way.
    if (_disposing) return;
    _disposing = true;
    call.removeListener(_onCallChanged);
    call.clearForegroundActions();
    _tick?.cancel();
    // A summary still holding its 3s when the holder discards the session --
    // logout, a redial stepping over -- must not fire into a disposed one.
    _summaryHold?.cancel();
    _summaryHold = null;
    _finishRecording();
    // ActiveCall.dispose hangs up (idempotent), so a session discarded by its
    // holder — logout, app teardown — can never leave a call running headless.
    call.dispose();
    super.dispose();
  }
}
