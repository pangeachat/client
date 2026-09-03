import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' show Logs;
import 'package:permission_handler/permission_handler.dart';

import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/calls/ring_player.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/calls/transcript_writer.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

import 'package:matrix/matrix.dart'
    as matrix
    show Event, EventStatusExtension, Room, User;

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

  /// The two strings the ANDROID platform renders for an ongoing call: the
  /// notification's mute button, and the channel's name in system settings.
  /// The plugin cannot translate them, so they are handed in from where a
  /// BuildContext exists. Null on every other platform, and in tests.
  final ({String mute, String channel})? platformLabels;

  final CallMedia media;
  final ActiveCall call;
  final CallRecord _record;

  /// The transcript publisher this session wired up, exposed so a test can
  /// prove the wiring EXISTS. Everything under this feature was built and
  /// green while nothing in the app ever wrote a transcript, because the
  /// publisher was optional and no caller supplied it. Parts that all work
  /// and are not connected read as a working feature and ship a dark one.
  @visibleForTesting
  TranscriptPublisher? get transcriptPublisher => _record.publishTranscript;

  /// The record this session writes through, exposed so a test can drive the
  /// REAL finish path. Calling the publisher directly proves only that a
  /// parameter exists; what needs proving is that the session fills it in.
  @visibleForTesting
  CallRecord get record => _record;

  final String? _myUserId;
  final String? _peerUserId;

  bool _muted = false;
  bool _camera = false;

  /// The last-seen ownership hold state, so the camera can be restored exactly
  /// once on the held->unheld edge.
  bool _wasMediaHeld = false;
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
    this.platformLabels,
    this.tonesOverride,
    bool fullscreen = false,
  }) : _record = record,
       _myUserId = myUserId,
       _peerUserId = peerUserId,
       _fullscreen = fullscreen,
       _onReleased = onReleased {
    _camera = videoRequested;
    // What the ongoing-call notification says. The call only knows the room;
    // the session knows who the conversation is with.
    call.foregroundLabel =
        peer?.calcDisplayname() ?? room.getLocalizedDisplayname();
    call.foregroundMuteLabel = platformLabels?.mute ?? '';
    call.foregroundChannelName = platformLabels?.channel ?? '';
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
    ({String mute, String channel})? platformLabels,

    /// Whether the call covers the whole app from its first frame. See
    /// [CallSession.fullscreen]: only a call answered on a non-active account
    /// asks for this, because it has no chat pane to be presented in.
    bool fullscreen = false,
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
    // Built here rather than inline below, because the half published at the
    // end of the call has to state how much audio the CAPTURE PATH lost --
    // audio that never became a chunk, so the sink has never heard of it and
    // no count it keeps can carry it.
    final capture = captureOverride ?? CallCaptureService(sink: transcripts);

    // WHO IS WRITING THIS HALF, READ ONCE, HERE, WHILE THE CALL IS BEING SET UP.
    //
    // These two are not description, they are the IDENTITY the transcript
    // half's transaction id is built from -- `(call key, sender, device)` --
    // and an idempotency key has to be frozen for the whole operation rather
    // than re-read per attempt. `CallRecord` retries a failed publish three
    // times and freezes everything else it sends before the first one, for
    // exactly this reason: a resend only collapses server-side if it is the
    // same event. Read inside the closure below, these two were the one part
    // of the key that could change between attempts. A send that the server
    // accepted but whose response was lost, followed by a client that dropped
    // its login before the retry, published the same speech under a second
    // transaction id with no `device_id` on it -- so the homeserver stored two
    // events and the reader, which now groups by device, showed the learner
    // two devices and merged the duplicate speech. That is the precise loss the
    // per-device keying exists to prevent, coming back in through the retry.
    //
    // Frozen at BUILD rather than at publish, because this is the device that
    // did the recording and the recording is what the half is about. By the
    // time the last chunk has drained, `client.deviceID` answers a different
    // question: which device is signed in NOW.
    final writerUserId = room.client.userID ?? '';
    final writerDeviceId = room.client.deviceID;

    final record =
        recordOverride ??
        CallRecord(
          roomId: room.id,
          transcripts: transcripts,
          sendEvent: (content, txid) =>
              room.sendEvent(content, type: PangeaEventTypes.call, txid: txid),
          // The transcript half this device writes when the call ends. Built
          // here rather than inside CallRecord so the record stays testable
          // without a room, and so the ONE place that knows about the room --
          // its id, and whether it encrypts -- is the place that knows.
          publishTranscript:
              ({
                required String callKey,
                required List<TranscriptSegment> segments,
                required int chunksCaptured,
                required int chunksTranscribed,
                required int chunksLost,
                required int chunksSuppressed,
                required bool captureRefused,
                required bool drainComplete,
                String? langCode,
              }) => writeCallTranscript(
                send: (content, txid) => room.sendEvent(
                  content,
                  type: CallTranscriptContent.relType,
                  txid: txid,
                ),
                callKey: callKey,
                // Both taken from the latches above, never read off the client
                // here: this closure runs once per RETRY, and the transaction
                // id built from these two is what makes a retry a retry.
                senderId: writerUserId,
                // The ACCOUNT above, and the DEVICE here, because they answer
                // two different questions and one of them used to answer both.
                // Two of a learner's devices in one call write two halves of
                // what that person said; keyed by the account alone those two
                // halves are indistinguishable, and the reader keeps one and
                // presents it as the whole of it.
                deviceId: writerDeviceId,
                segments: segments,
                chunksCaptured: chunksCaptured,
                chunksTranscribed: chunksTranscribed,
                chunksLost: chunksLost,
                chunksSuppressed: chunksSuppressed,
                captureRefused: captureRefused,
                drainComplete: drainComplete,
                // Read here rather than threaded through the record's
                // publisher, the same seam that already closes over the
                // clock anchor below. Both are frozen long before this can
                // run -- the recorder ends its last run, which is the only
                // thing that discards a chunk or counts a dropped one, and
                // only then closes the sink the record waits on -- so the
                // record's rule that a resend must carry the same bytes
                // holds for them as it does for the counts it reads once.
                chunksDiscarded: transcripts.chunksDiscarded,
                captureDroppedMs: capture.captureDroppedMs,
                // Read from the same seam and frozen by the same ordering: a
                // run's extent is recorded where the run ends, and the last run
                // has ended before the sink this record waits on is closed. The
                // count above says a stretch was handed over; these say WHICH,
                // which is what lets a reader ask whether the sibling that was
                // supposed to hold it actually did.
                keptSpans: capture.keptSpans,
                discardedSpans: capture.discardedSpans,
                // The room inflates what it is handed, and the server's limit
                // applies to the inflated event.
                encrypted: room.encrypted,
                langCode: langCode,
                // Read from the LATCH here, not measured here. It was taken
                // when this device joined the SFU, minutes before this runs,
                // and reading the two clocks now would measure the call's own
                // length instead of the disagreement between them.
                //
                // Closed over rather than threaded through CallRecord: the
                // record is deliberately free of anything to do with media,
                // and this is the same seam that already knows the room.
                clockAnchor: media.clockAnchor,
              ),
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
        capture: capture,
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
      platformLabels: platformLabels,
      fullscreen: fullscreen,
      tonesOverride: tonesOverride,
    );
  }

  // ---------------------------------------------------------------- state

  bool get minimized => _minimized;

  /// Whether the call is showing over the whole app rather than inside its
  /// chat pane. A choice, not the default: the pane is where the call lives,
  /// and this is the "make it big" button every video product offers.
  ///
  /// Seeded by the constructor rather than only toggled, because one caller
  /// needs it true from the very first frame. A call answered on an account
  /// that is not the foregrounded one has no chat pane to live in -- its room
  /// belongs to another account, so navigating there would land on
  /// `RoomUnavailablePanel` -- and it is presented by [GlobalCallTile]
  /// instead. That tile renders the full [CallPanel] only when this is true;
  /// otherwise it renders `CallMiniTile`, which has neither hangup nor mute.
  /// Toggling after the session is published to `activeCall` would paint one
  /// frame of a call the learner has just answered and cannot end.
  bool get fullscreen => _fullscreen;
  bool _fullscreen;

  void toggleFullscreen() {
    _fullscreen = !_fullscreen;
    if (_fullscreen) _minimized = false;
    _notify();
  }

  /// Makes the call cover the whole app, and KEEPS it there.
  ///
  /// Idempotent, which [toggleFullscreen] is not. This is reached from a tap
  /// on the floating tile for a call whose room cannot be navigated to -- one
  /// on an account that is not the foregrounded one -- and two taps delivered
  /// before that tile rebuilds would turn fullscreen straight back off,
  /// dropping the learner into `CallMiniTile`, which has neither hangup nor
  /// mute. A toggle is the wrong verb for "show me this call".
  void showFullscreen() {
    if (_fullscreen && !_minimized) return;
    _fullscreen = true;
    _minimized = false;
    _notify();
  }

  /// True while the ownership hold has the microphone closed, whatever the
  /// learner's OWN intent -- the panel shows muted-and-disabled then, and the
  /// intent is restored on resume.
  bool get muted => call.mediaHeld || _muted;

  /// False while the ownership hold has the camera closed, for the same reason.
  bool get cameraOn => !call.mediaHeld && _camera;

  /// Whether a capture device could not be opened at all. The call is up and
  /// looks normal; the other person hears nothing.
  bool get microphoneRefused => media.captureRefused;
  bool get isOver => _over;
  bool get hasPresenter => _presenters > 0;

  /// The failure to show, when the call could not be established. The session
  /// stays alive in this state — a screen that vanishes on failure is
  /// indistinguishable from a crash — until [dismissFailed].
  bool get isFailed => call.outcome == CallOutcome.failed;

  /// Whether this device left because the learner is carrying the call on
  /// another of their devices -- the summary then says the call continues
  /// elsewhere rather than that it ended.
  bool get movedToOtherDevice => call.outcome == CallOutcome.movedToOtherDevice;

  CallStage get stage => call.stage;
  Object? get error => call.error;
  bool get isReconnecting => call.isReconnecting;
  bool get peerReconnecting => call.peerReconnecting;
  bool get peerMuted => call.peerMuted;

  /// Whether the ownership arbiter is holding this device's media closed.
  bool get mediaHeld => call.mediaHeld;

  /// What the two-devices-one-call arbiter is asking the learner, or null.
  OwnershipPrompt? get ownershipPrompt => call.ownershipPrompt;

  /// The learner tapped "Use this device": keep the call here.
  void chooseThisDevice() => call.chooseThisDevice();

  /// The learner tapped "Leave the call here": leave, keep it on the other one.
  void leaveForOtherDevice() => call.leaveForOtherDevice();
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
        case 'promotion-failed':
          call.foregroundRefused();
        case 'types-refused':
          // The service is up and the call is protected; Android just would
          // not add the camera to what it says the service is doing. Nothing
          // to reclaim -- taking the claim back here would leave the running
          // service with nobody to stop it.
          Logs().w('The call service could not add the camera type');
      }
    });
  }

  Future<void> toggleMute() async {
    // The ownership hold does not let the controls OPEN the microphone, on any
    // surface -- this is also the foreground notification's mute path. The
    // learner's own intent is preserved for resume rather than overwritten.
    if (call.mediaHeld) {
      Logs().i('Microphone control ignored while held by the devices prompt');
      return;
    }
    final next = !_muted;
    // The recorder gate goes up BEFORE muting and comes down only AFTER an
    // unmute has taken — never while the microphone is still muted. On Android
    // the recorder tap runs upstream of LiveKit's publish mute, so without its
    // own gate a muted learner would still be recorded.
    if (next) call.setMuted(true);
    final bool publishing;
    try {
      publishing = await media.setMicrophoneEnabled(!next);
    } catch (e, s) {
      // Fail closed: a mute that did not take must ungate again (the mic is
      // still live); an unmute that did not take leaves the gate up.
      if (next) call.setMuted(false);
      Logs().w('Could not ${next ? 'mute' : 'unmute'} the call', e, s);
      return;
    }
    // The same rule, for the failure that does not throw. Turning the
    // microphone on either publishes or throws, so `false` from an UNMUTE is
    // the microphone not publishing -- a call already released, or no
    // participant to publish through -- and it comes back as quietly as a
    // toggle that worked. Leaving the gate up and `_muted` set is the second
    // half of the rule above: the button must not say the learner is being
    // heard while nothing of theirs is going out, and the recorder must not
    // come off the gate for a microphone that never came back.
    //
    // Only the unmute direction is disproved by this answer. `false` from a
    // MUTE means there was no publication to stop, which `CallMedia` documents
    // as a no-op rather than a failure -- reading the answer both ways would
    // leave a learner unable to mute a call whose room had already gone.
    if (!next && !publishing) {
      Logs().w('The call could not unmute; the microphone is not publishing');
      return;
    }
    if (!next) call.setMuted(false);
    if (_disposing || _over) return;
    _muted = next;
    _notify();
  }

  Future<void> toggleCamera() async {
    if (call.mediaHeld) {
      Logs().i('Camera control ignored while held by the devices prompt');
      return;
    }
    final next = !_camera;
    final bool live;
    try {
      live = await media.setCameraEnabled(next);
    } catch (e, s) {
      Logs().w('Could not turn the camera ${next ? 'on' : 'off'}', e, s);
      return;
    }
    // Nothing downstream of here may act on the request alone. Turning the
    // camera on the instant the call ends is a refused no-op that does NOT
    // throw, and acting on it anyway wrote an ending voice call into the
    // timeline as a video call, offered a camera-OFF button for a picture that
    // was never coming, and told the foreground service the call was using a
    // camera it had not opened.
    //
    // The proof is the toggle's own answer -- whether a track ended up
    // published -- rather than the connection being up, which is a proxy for it
    // and can outlast the refusal it was standing in for: the release the
    // refusal comes from is latched inside the media, while the socket it
    // guards takes a round trip to close.
    //
    // Only the ON direction is disproved by this answer, exactly as in
    // [toggleMute]: `false` turning the camera OFF means there was no
    // publication to stop, which is a no-op and not a failure.
    if (next && !live) {
      Logs().w('The call could not turn the camera on; nothing was published');
      return;
    }
    // Camera site (b): the toggle, both directions, only after the change
    // actually took. Site (a) -- a call STARTED with video -- lives where the
    // camera opens, inside the call's own connect step.
    unawaited(call.setForegroundCamera(next));
    // The video claim goes in the timeline and stays there, so it is the one
    // that most needs to be read off the effect; the guard above is what makes
    // reaching here with `next` set mean the camera came on.
    if (next) _usedVideo = true;
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
    // The ownership hold has just resumed: reopen the camera to the learner's
    // own intent (the arbiter reopened the microphone; the camera intent lives
    // here). ONLY for the SURVIVOR carrying on -- a device whose hold clears
    // because it is LEAVING (chosen against, or a give-up) has its media torn
    // down, and reopening the camera there would republish it on a device on
    // its way out. Gated on carriedOn, not merely on the held->unheld edge.
    if (_wasMediaHeld && !call.mediaHeld && call.carriedOn) {
      unawaited(media.setCameraEnabled(_camera));
    }
    _wasMediaHeld = call.mediaHeld;
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
    if (outcome != null) {
      // A device that did NOT carry on -- held then never resumed, walked away
      // from, or given up because nobody chose it -- leaves no trace: no card,
      // no transcript half, no analytics, no summary (doc:236). Keyed on the
      // FACT (carriedOn), not on which outcome fired, so an ordinary `ended`
      // reached while held is caught alongside `movedToOtherDevice`.
      if (!call.carriedOn) {
        _finish();
        // A MOVED leave still says WHY (the panel reads the outcome), so it
        // earns a brief moment on screen; a give-up goes at once.
        if (outcome == CallOutcome.movedToOtherDevice) {
          _summaryHold = Timer(summaryLifetime, _handover);
          _notify();
        } else {
          _handover();
        }
        return;
      }
      // The card FIRST and immediately: everything it states is known now, and
      // it must not wait for teardown and transcription behind it.
      //
      // EVERY outcome, a FAILURE included, which is what this used to miss.
      // A failed call was recorded from [dismissFailed] instead, and that
      // reaches the record but not this -- and this is where the card's fast
      // path AND the survivor check both hang. So a call that rang somebody
      // and then failed on our end could never recover a dead writer's card,
      // and a learner who closed the tab rather than pressing the X left
      // nothing behind at all. The two paths had drifted apart on which of
      // them owns "what does this call leave", and the answer is: whichever
      // one sees the call's fate, which is only ever this one.
      _writeCard();
    }
    if (outcome == CallOutcome.ended || outcome == CallOutcome.declined) {
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
  ///
  /// [_reachedCall] only means OUR OWN join to the SFU went through — it says
  /// nothing about whether the other side was ever told. That distinction did
  /// not used to matter: reaching "connected" required the ring to have gone
  /// out first, so one implied the other. It stopped being true the moment
  /// ringing could be skipped and retried in the background (a late
  /// membership echo) — a PLACED call can now reach the SFU while its ring is
  /// still pending, or never sent at all if the retry itself runs out. When
  /// that happens and nobody ever joins, [_reachedCall] is the only thing left
  /// standing in for "this mattered", and it is lying: hanging up would write
  /// "no answer" for a call the other person was never rung for. So a placed
  /// call only counts on [_reachedCall] once it is also known to have rung —
  /// [call.rangOut] already covers that case on its own, this guard just keeps
  /// [_reachedCall] from covering it a second time, dishonestly, when it
  /// didn't. Every other placer (answering, rejoining, the sub-millisecond
  /// glare that never places) is untouched: none of them ring, so none of
  /// them relied on this in the first place.
  ///
  /// A ring is a ring whichever side sent it, which is what the guard above
  /// first missed. [ActiveCall.peerAlsoPlaced] is set from THEIR ring
  /// arriving here -- a real ring, from a device still holding a call -- so a
  /// call back that looks like glare is a call somebody was already rung for,
  /// and the guard asking only about OUR ring silenced it. That is the
  /// survivor's shape exactly: the peer rings, dies before writing its card,
  /// we call back, the tie-break hands the writing to the dead device, and
  /// our own ring never goes out. Everything downstream of here was ready to
  /// recover that call -- the survivor check runs on the same
  /// [ActiveCall.peerAlsoPlaced] -- and this getter never let it start, so
  /// the original ring left nothing in the conversation at all.
  bool get _mattered =>
      (_reachedCall &&
          (!call.placedCall || call.rangOut || call.peerAlsoPlaced)) ||
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
            anchorEventId: notificationEventId ?? call.callAnchorId,
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
  /// but only when it is entitled to stand in at all (see
  /// [_mayStandInForTheWriter]), only with a ring- or glare-provenanced key
  /// (a rejoined session's anchor may be its own membership, the wrong key),
  /// and stamped with the same shared key so the renderer collapses the rare
  /// race where both raced to write.
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

  /// Whether this device may stand in for a writer that never wrote.
  ///
  /// Its own question, and NOT the negation of [_writesTheCall]. That one is
  /// about placing a call; this one is about a call somebody else was on and
  /// nobody recorded, and reading the second off the first is what kept the
  /// recovery from doing its job for an ordinary callee.
  ///
  /// Somebody else was on this call if they ARRIVED, or if a ring of theirs
  /// reached this device -- the one we answered, or the one that made a call
  /// back look like glare. One fact by three routes, and the gate knew only
  /// two of them: a plain CALLEE, rung by a caller whose app then died, was
  /// refused. That call rang somebody -- us -- and it left the conversation
  /// with nothing, which is the whole failure this path exists to prevent.
  ///
  /// A ring on its own is not enough, and that is the true thing the old gate
  /// was groping at by demanding somebody had arrived. A ring says the writer
  /// EXISTED, not that it has finished. So a device standing in on the
  /// strength of a ring must also have GONE AND LOOKED: reached the call and
  /// found nobody there. That is an observation rather than an inference --
  /// a caller is in the SFU before it rings, so an empty call is a caller who
  /// has gone -- while a session that failed before it ever got in knows only
  /// that a ring arrived. A card from there would be a guess, and one landing
  /// EARLIER than the truthful card a living caller is still about to write.
  ///
  /// A fabrication is impossible in either direction: the survivor's card
  /// carries [ActiveCall.hadPeer] and [ActiveCall.wasDeclined], this side's
  /// own observations, so it can neither invent a conversation nor invent a
  /// refusal.
  bool get _mayStandInForTheWriter =>
      call.hadPeer ||
      ((call.peerAlsoPlaced || notificationEventId != null) && _reachedCall);

  void _scheduleSurvivorCheck(({String? key, String? caller}) identity) {
    // Through the record's own rule: an empty key identifies nothing, and a
    // survivor writing under one would post a card that every reader either
    // ignores or, worse, collapses against an unrelated call's.
    final key = CallRecord.usableKey(identity.key);
    if (_writesTheCall ||
        !_mayStandInForTheWriter ||
        call.rejoinedCall ||
        key == null) {
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
    // Through the same question the timeline asks, not a private copy of it.
    //
    // This decided "a card for this call already exists" on type and key
    // alone. The key is the caller's membership event id, which every room
    // member can see DURING the call -- so anyone could post a card carrying
    // it inside the settle window, this check would find it, and the real
    // survivor card would never be written. The timeline then correctly
    // refuses to draw the forgery, and the call is left with no card from
    // anybody: gone from the conversation and from the chat list, taking the
    // transcript it opens with it.
    //
    // A send that failed does not count either. It is kept locally and marked
    // errored, nothing retries it, and the peer never receives it, so treating
    // it as a card already written suppresses the one write that would have
    // reached them.
    final already = events.any(
      (e) =>
          e.type == PangeaEventTypes.call &&
          CallRecord.keyOf(e.content) == key &&
          !e.status.isError &&
          // PROVEN, for the same reason as suppression: this decides whether
          // to SKIP writing the real card, so a card that cannot vouch for
          // itself must not be able to stop us. Where the peer is unknown we
          // write, and the conversation may show two cards for one call --
          // which is visible and harmless, unlike the call having no card at
          // all because a stranger's forgery told us one already existed.
          callCardIsProvenReal(e),
    );
    if (already) return;
    Logs().i('No card arrived for this call; the survivor writes it');
    await _record.writeSurvivorCard(
      duration: call.talkDuration,
      video: _usedVideo,
      callKey: key,
      // What THIS side saw. The survivor path also covers the case where
      // nobody ever arrived -- a call back that looked like glare because the
      // other app died mid-ring -- and calling that answered would invent a
      // conversation out of a ring nobody picked up.
      answered: call.hadPeer,
      declined: call.wasDeclined,
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
            // The card is normally already in the timeline by now (written the
            // moment the call ended); this call credits the transcripts against
            // it, and writes the card itself only if that earlier attempt had
            // failed outright.

            final identity = _callIdentity;
            return _record.finish(
              duration: call.talkDuration,
              video: _usedVideo,
              // Whether the call earned any trace: it got established, it
              // actually rang the other side, or it was itself an answer.
              // Placing alone is not enough -- a call whose announce failed
              // rang nobody, and anything left behind for it would record a
              // call that never began.
              //
              // Handed over rather than acted on here. Returning early instead
              // left the record free to publish this device's transcript half
              // for a call it was about to decide had never happened, and
              // nothing in the record said otherwise; the half stayed out of
              // the room only because such a call also has no key to publish
              // under. One decision, stated once, enforced where the writing
              // is.
              mattered: _mattered,
              // Our own failure, not a statement about the speaker.
              captureRefused: microphoneRefused,
              answered: call.hadPeer,
              declined: call.wasDeclined,
              writeTimelineEvent: _writesTheCall,
              callerId: identity.caller,
              callKey: identity.key,
              anchorEventId: notificationEventId ?? call.callAnchorId,
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
    ownMembershipId: call.callAnchorId,
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

  /// How long the CALL lasted, for the summary that follows it.
  ///
  /// The same clock the timer on screen was counting, so the number the
  /// learner watched reach 1:08 is the number they are shown a second later.
  /// [ActiveCall.talkDuration] is the segmented time anyone could actually be
  /// heard -- right for the card and the analytics, and wrong here: after a
  /// rejoin it counts only the stretch since returning, so a call the learner
  /// had just watched run to 1:08 ended with a summary reading 0:14.
  Duration get callDuration {
    final began = callStartedAt;
    if (began == null) return call.talkDuration;
    final until = _endedAt ?? DateTime.now();
    final span = until.difference(began);
    return span.isNegative ? call.talkDuration : span;
  }

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
