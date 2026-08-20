import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix show Room, User;
import 'package:matrix/matrix.dart' show Logs;

import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

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
  }) : _record = record,
       _myUserId = myUserId,
       _peerUserId = peerUserId,
       _onReleased = onReleased {
    _camera = videoRequested;
    call.addListener(_onCallChanged);
    call.start(
      room,
      video: videoRequested,
      // Being rung is what makes this an answer. Derived from the room it
      // would be wrong exactly when the caller had already given up.
      answering: notificationEventId != null,
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
    @visibleForTesting CallMedia? mediaOverride,
    @visibleForTesting CallCaptureService? captureOverride,
  }) {
    final media = mediaOverride ?? CallMedia();
    final transcripts = CallTranscriptSink(
      transcribe: transcribe,
      userL1: userL1,
      userL2: userL2,
    );
    final record = CallRecord(
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
      ),
      record: record,
      myUserId: callService.client.userID,
      peerUserId: room.directChatMatrixID,
      onReleased: onReleased,
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
  bool get hadPeer => call.hadPeer;
  bool get placedCall => call.placedCall;
  DateTime? get talkStartedAt => call.talkStartedAt;
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
    // The outcome is latched the instant the call's fate is decided, seconds
    // before the stage catches up — this is what makes hanging up feel
    // immediate on both sides.
    final outcome = call.outcome;
    if (outcome == CallOutcome.ended || outcome == CallOutcome.declined) {
      _finishRecording();
      _release();
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
            final mattered =
                _reachedCall ||
                call.hadPeer ||
                // The ATTEMPT, not the id: a ring whose responses were both
                // lost still rang their phone, and that call must leave its
                // missed-call card. A call whose announce failed never rang
                // and correctly leaves nothing.
                call.rangOut ||
                notificationEventId != null;
            if (!mattered) return;
            return _record.finish(
              duration: call.talkDuration,
              video: _usedVideo,
              answered: call.hadPeer,
              declined: call.wasDeclined,
              writeTimelineEvent: _writesTheCall,
              callerId: call.placedCall ? _myUserId : _peerUserId,
              anchorEventId: notificationEventId ?? call.membershipEventId,
            );
          })
          .catchError((Object e, StackTrace s) {
            Logs().e('Could not finish the call recording', e, s);
          }),
    );
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

  void _release() {
    if (_over) return;
    _over = true;
    _tick?.cancel();
    _tick = null;
    _notify();
    _onReleased(this);
  }

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
    _tick?.cancel();
    _finishRecording();
    // ActiveCall.dispose hangs up (idempotent), so a session discarded by its
    // holder — logout, app teardown — can never leave a call running headless.
    call.dispose();
    super.dispose();
  }
}
