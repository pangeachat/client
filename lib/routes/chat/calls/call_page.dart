import 'dart:async';

import 'package:flutter/material.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix show Room, User;

import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_repo.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The in-call screen.
///
/// Pushed rather than routed: a call is modal for as long as it lasts, and there
/// is nothing to deep-link to — a URL pointing at a call that has ended is worse
/// than no URL at all. Ringing, when it lands, needs a route; this does not.
class CallPage extends StatefulWidget {
  final matrix.Room room;
  final bool video;

  /// The notification this device was rung with, when answering.
  ///
  /// Null when placing a call. The answering side does not write the call to
  /// the timeline — the caller does — so this is what its speaking analytics
  /// are anchored to instead.
  final String? notificationEventId;

  const CallPage({
    required this.room,
    required this.video,
    this.notificationEventId,
    super.key,
  });

  static Future<void> show(
    BuildContext context,
    matrix.Room room, {
    required bool video,
    String? notificationEventId,
    // The ROOT navigator, not the enclosing one. On a wide window the chat sits
    // in a pane with its own navigator, and pushing there rendered the call
    // inside that pane — clipped at the pane's edge, which cut the controls off
    // the bottom. A call is modal for as long as it lasts; it takes the screen.
  }) => Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallPage(
        room: room,
        video: video,
        notificationEventId: notificationEventId,
      ),
    ),
  );

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late final CallMedia _media;
  late final ActiveCall _call;
  late final CallRecord _record;

  /// Whether this device got as far as an established call. A call that failed
  /// to start is not written at all; one that rang out unanswered is, as a
  /// missed call.
  bool _reachedCall = false;

  /// Whether the camera was ever on. The call is recorded by what happened, not
  /// by what was asked for — a voice call someone turns their camera on during
  /// is a video call, and writing otherwise would put something untrue in the
  /// learner's timeline.
  late bool _usedVideo;
  bool _muted = false;
  late bool _camera;

  /// Redraws once a second so the timer advances. Nothing else on this screen
  /// changes on its own, so it runs only while a call is actually up.
  Timer? _tick;

  /// Read while the screen is alive; used after it is gone.
  String? _myUserId;
  String? _peerUserId;

  @override
  void initState() {
    super.initState();
    _camera = widget.video;
    _usedVideo = widget.video;
    _media = CallMedia();

    // Everything the recording needs is captured HERE, while the screen is
    // alive: the analytics service, the room, the learner's languages. The call
    // ends when the user closes this screen, so anything read later would be
    // read from a context that has already gone.
    final matrix = Matrix.of(context);
    // Captured now, not read later: this screen is gone by the time the record
    // is written, and reading an inherited widget from a deactivated context
    // throws — which would cost the call its analytics entirely.
    _myUserId = matrix.client.userID;
    _peerUserId = widget.room.directChatMatrixID;
    final user = MatrixState.pangeaController.userController;
    final transcripts = CallTranscriptSink(
      // The repo answers with a Result; the sink's contract is a value or a
      // throw, and it already treats a throw as "this chunk's words are lost".
      transcribe: (request) async {
        final result = await SpeechToTextRepo.instance.get(request);
        final value = result.asValue;
        if (value == null) {
          throw result.asError?.error ?? StateError('speech-to-text failed');
        }
        return value.value;
      },
      userL1: user.userL1Code ?? LanguageKeys.unknownLanguage,
      userL2: user.userL2Code ?? LanguageKeys.unknownLanguage,
    );
    final room = widget.room;
    _record = CallRecord(
      roomId: room.id,
      transcripts: transcripts,
      // Its own event type, not a room message. A call is something that
      // HAPPENED in the conversation, so it belongs in the timeline as a
      // centred entry beside joins and invitations — not as a chat bubble
      // attributed to one side and aligned to their edge.
      sendEvent: (content, txid) =>
          room.sendEvent(content, type: PangeaEventTypes.call, txid: txid),
      analytics: (eventId, uses, language) => matrix
          .analyticsDataService
          .updateService
          .addAnalytics(eventId, uses, language),
    );

    _call = ActiveCall(
      calls: matrix.callService,
      media: _media,
      capture: CallCaptureService(sink: transcripts),
    )..addListener(_onCallChanged);
    // Being rung is what makes this an answer. Derived from the room it would
    // be wrong exactly when the caller had already given up.
    _call.start(
      room,
      video: widget.video,
      answering: widget.notificationEventId != null,
    );
  }

  void _onCallChanged() {
    if (!mounted) return;
    setState(() {});
    if (_call.stage == CallStage.connected) _reachedCall = true;
    // Started on somebody arriving, not on reaching the connected stage. A peer
    // who was already here when this device joined is present before the stage
    // moves, and gating the timer on the stage left a call that ended in that
    // window showing — and recording — no talking at all.
    if (_call.hadPeer) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    // A call that ended or failed has nothing left to show. Closing here rather
    // than leaving a dead screen up means the user never has to dismiss a call
    // that is already over.
    if (_call.stage == CallStage.ended ||
        _call.stage == CallStage.failed ||
        _call.stage == CallStage.declined) {
      _tick?.cancel();
      _tick = null;
      // Deliberately not awaited and deliberately not tied to this widget: the
      // recording outlives the screen, which is closing on the next line.
      _finishRecording();
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    // Leaving by system back, a dismiss gesture, or the route being removed
    // never runs the listener below, so the recording would be silently lost on
    // an entirely ordinary exit. finish() is idempotent, so calling it here as
    // well is safe when the listener did run.
    _tick?.cancel();
    _finishRecording();
    _call.removeListener(_onCallChanged);
    // ActiveCall.dispose hangs up. Leaving the screen ends the call — there is no
    // background call in v1, and a call still running behind a closed screen is
    // one the user cannot hang up.
    _call.dispose();
    super.dispose();
  }

  /// Ends the call, then writes it and its analytics.
  ///
  /// **Every** way of leaving goes through here — both hangup buttons, the ended
  /// listener, and disposal. A path that only hung up would stamp the end time
  /// late and might never write the call at all.
  ///
  /// The order matters: hanging up is what flushes the last chunk of audio and
  /// waits for it to be transcribed, so writing first would anchor whatever had
  /// arrived and mark it done, losing the end of what the learner said.
  ///
  /// `hangUp` is idempotent and returns the same teardown to every caller, so
  /// the several entry points wait on one teardown and write once. Deliberately
  /// not awaited and not tied to this widget — it outlives the screen.
  void _finishRecording() {
    unawaited(
      // whenComplete, not then: a teardown that throws must not also cost the
      // call its record. The write is what turns a conversation into analytics,
      // and it is correct whether or not the unwind was clean.
      _call.hangUp().whenComplete(() async {
        // Let a start still unwinding finish before deciding what to write.
        // After the hangup, never before it: teardown must not wait on the
        // network, but the record must know whether the ring went out.
        try {
          await _call.settled;
        } catch (_) {}
        // Written when the call either got established OR rang the other side.
        // Reaching the SFU alone was too narrow: hanging up while still
        // connecting skipped the record even though their phone had already
        // rung, so a call someone saw and missed left no trace anywhere. A call
        // that rang nobody and connected to nothing is still not written —
        // nothing happened, and an entry would record a call that never began.
        // Did this call ever exist for anyone: did it reach the SFU, did we
        // ring somebody, or were we rung. The last of those is the answering
        // side, which never rings and so never has a notification of its own —
        // checking only the outbound one lost its speaking analytics whenever
        // the caller left before the call finished coming up.
        final mattered =
            _reachedCall ||
            _call.hadPeer ||
            _call.placedCall ||
            _call.notificationEventId != null ||
            widget.notificationEventId != null;
        if (!mattered) return;
        return _record.finish(
          // Time actually spent talking, not time the screen was open. Ringing
          // and connecting are not conversation, and counting them made every
          // call read as longer than it was.
          duration: _call.talkDuration,
          video: _usedVideo,
          // Whether anyone was ever on the other end, read from the call
          // itself. Latching this on observing the connected stage dropped a
          // real case: a peer who was present and left while we were still
          // announcing meant the stage never reached connected, and a call that
          // genuinely had someone on it was recorded as missed.
          answered: _call.hadPeer,
          declined: _call.wasDeclined,
          writeTimelineEvent: _writesTheCall,
          callerId: _call.placedCall ? _myUserId : _peerUserId,
          // The ring we answered, or failing that our own membership in the
          // call. The two sides of a call do not have to anchor to the same
          // event — they never have: whoever answers anchors to the ring, and
          // whoever called anchors to the card. What an anchor has to be is a
          // real event of this call that can be traced back to it, and a
          // membership is exactly that. A device that joined a call already under way has neither a
          // ring of its own nor one it answered, and with nothing to anchor to
          // every word its learner spoke was dropped.
          anchorEventId: widget.notificationEventId ?? _call.membershipEventId,
        );
      }),
    );
  }

  /// Whether this device writes the call to the room.
  ///
  /// The side that placed it writes it, because a call nobody answers only ever
  /// runs this teardown on the caller's side — deciding by comparing user ids
  /// instead made every missed call vanish whenever the caller sorted second.
  ///
  /// When both people called at the same moment both placed it, and both would
  /// write. Their ring tells us that happened, and the two ids then settle which
  /// of the two writes. Reads only values captured while the screen was alive.
  bool get _writesTheCall {
    if (!_call.placedCall) return false;
    if (!_call.peerAlsoPlaced) return true;
    final me = _myUserId;
    final peer = _peerUserId;
    if (me == null || peer == null) return true;
    return me.compareTo(peer) < 0;
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await _media.setMicrophoneEnabled(!next);
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _toggleCamera() async {
    final next = !_camera;
    await _media.setCameraEnabled(next);
    if (next) _usedVideo = true;
    if (mounted) setState(() => _camera = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final tracks = _videoTracks();

    return Scaffold(
      // Its own surface rather than the app's. A call takes over the screen, and
      // every calling product darkens it — a flat container colour read as an
      // unfinished page with a hole in it.
      backgroundColor: const Color(0xFF14131A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video fills the screen when there is any; a voice call keeps the
          // gradient, so the screen never looks like it failed to load.
          if (tracks.isNotEmpty) _videoLayer(tracks) else _voiceBackdrop(theme),
          SafeArea(
            child: Column(
              children: [
                _topBar(l10n),
                Expanded(
                  child: tracks.isNotEmpty
                      ? const SizedBox.shrink()
                      // Scrollable so a short window shrinks the panel rather
                      // than pushing the controls off the bottom. Hanging up
                      // must never be the thing that goes missing.
                      : Center(
                          child: SingleChildScrollView(
                            child: _peerPanel(l10n, theme),
                          ),
                        ),
                ),
                if (tracks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _status(l10n),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    l10n.callRecordingNotice,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white38,
                    ),
                  ),
                ),
                _controls(l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _voiceBackdrop(ThemeData theme) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          theme.colorScheme.primary.withValues(alpha: 0.28),
          const Color(0xFF14131A),
        ],
      ),
    ),
  );

  Widget _topBar(L10n l10n) => Align(
    alignment: Alignment.centerLeft,
    child: IconButton(
      icon: const Icon(Icons.expand_more, color: Colors.white),
      tooltip: l10n.callHangUp,
      onPressed: _finishRecording,
    ),
  );

  /// Who is on the call, and what it is doing.
  Widget _peerPanel(L10n l10n, ThemeData theme) {
    final peer = _peer();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Avatar(
          mxContent: peer?.avatarUrl,
          name:
              peer?.calcDisplayname() ?? widget.room.getLocalizedDisplayname(),
          size: 108,
          showPresence: false,
        ),
        const SizedBox(height: 20),
        Text(
          peer?.calcDisplayname() ?? widget.room.getLocalizedDisplayname(),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        if (peer != null) ...[
          const SizedBox(height: 4),
          Text(
            peer.id,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          _status(l10n),
          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  /// The other person in a direct message, for the name and face on screen.
  ///
  /// The room's own name is the fallback rather than the answer: a direct chat
  /// renamed to something else would otherwise leave the call screen showing
  /// anything but who is on it.
  matrix.User? _peer() {
    final id = widget.room.directChatMatrixID;
    if (id == null) return null;
    return widget.room.unsafeGetUserFromMemoryOrFallback(id);
  }

  /// One line saying what the call is doing, which is the whole content of a
  /// voice call's screen — silence with no explanation is what makes a call
  /// feel broken.
  String _status(L10n l10n) {
    switch (_call.stage) {
      case CallStage.connecting:
        return _call.placedCall ? l10n.callRinging : l10n.callConnecting;
      case CallStage.connected:
        if (!_call.hadPeer) return l10n.callRinging;
        return _formatDuration(_elapsed());
      case CallStage.failed:
        return l10n.callFailed;
      case CallStage.ended:
        return l10n.callEnded;
      case CallStage.declined:
        return l10n.callDeclinedByPeer;
    }
  }

  Duration _elapsed() {
    final since = _call.talkStartedAt;
    if (since == null) return Duration.zero;
    return DateTime.now().difference(since);
  }

  static String _formatDuration(Duration d) {
    final seconds = d.inSeconds;
    final s = (seconds % 60).toString().padLeft(2, '0');
    final m = (seconds ~/ 60) % 60;
    final h = seconds ~/ 3600;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
    return '$m:$s';
  }

  /// Every published video track in the call, this device's included.
  ///
  /// Audio needs no widget — LiveKit plays remote audio itself — so a voice call
  /// has none, and that is correct rather than a missing case.
  /// Every video track on the call, ours and theirs.
  ///
  /// Latches [_usedVideo] on the way past. The timeline records what happened
  /// rather than what was asked for, and the peer turning their camera on makes
  /// this a video call just as surely as our own — reading only our own switch
  /// wrote a call the two people watched each other on as a voice call. Asked
  /// here because this is the one place that cannot miss it: there is no
  /// notification for a remote camera, but nothing can appear on screen without
  /// coming through this.
  List<lk.VideoTrack> _videoTracks() {
    final tracks = <lk.VideoTrack>[
      ..._media.room.remoteParticipants.values
          .expand((p) => p.videoTrackPublications)
          .map((p) => p.track)
          .whereType<lk.VideoTrack>(),
      ...?_media.room.localParticipant?.videoTrackPublications
          .map((p) => p.track)
          .whereType<lk.VideoTrack>(),
    ];
    if (tracks.isNotEmpty) _usedVideo = true;
    return tracks;
  }

  /// The peer full-bleed with this device inset, the layout every video call
  /// uses — a two-up grid would give our own face equal billing with theirs.
  Widget _videoLayer(List<lk.VideoTrack> tracks) => Stack(
    fit: StackFit.expand,
    children: [
      lk.VideoTrackRenderer(tracks.first),
      if (tracks.length > 1)
        Positioned(
          right: 16,
          top: 72,
          width: 108,
          height: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: lk.VideoTrackRenderer(tracks[1]),
          ),
        ),
    ],
  );

  Widget _controls(L10n l10n) {
    final live = _call.stage == CallStage.connected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28, top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CallButton(
            icon: _muted ? Icons.mic_off : Icons.mic,
            label: _muted ? l10n.callUnmute : l10n.callMute,
            background: Colors.white.withValues(alpha: 0.14),
            foreground: Colors.white,
            onPressed: live ? _toggleMute : null,
          ),
          const SizedBox(width: 22),
          _CallButton(
            icon: Icons.call_end,
            label: l10n.callHangUp,
            background: const Color(0xFFD32F2F),
            foreground: Colors.white,
            large: true,
            onPressed: _finishRecording,
          ),
          const SizedBox(width: 22),
          _CallButton(
            icon: _camera ? Icons.videocam : Icons.videocam_off,
            label: _camera ? l10n.callCameraOff : l10n.callCameraOn,
            background: Colors.white.withValues(alpha: 0.14),
            foreground: Colors.white,
            onPressed: live ? _toggleCamera : null,
          ),
        ],
      ),
    );
  }
}

/// A round call control with its name under it.
class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final bool large;
  final VoidCallback? onPressed;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 66.0 : 56.0;
    final disabled = onPressed == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: disabled ? 0.4 : 1,
          child: Material(
            color: background,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, color: foreground, size: large ? 30 : 24),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 84,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.white60),
          ),
        ),
      ],
    );
  }
}
