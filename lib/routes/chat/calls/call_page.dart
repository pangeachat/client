import 'dart:async';

import 'package:flutter/material.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix show Room;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_sink.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_repo.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The in-call screen.
///
/// Pushed rather than routed: a call is modal for as long as it lasts, and there
/// is nothing to deep-link to — a URL pointing at a call that has ended is worse
/// than no URL at all. Ringing, when it lands, needs a route; this does not.
class CallPage extends StatefulWidget {
  final matrix.Room room;
  final bool video;

  const CallPage({required this.room, required this.video, super.key});

  static Future<void> show(
    BuildContext context,
    matrix.Room room, {
    required bool video,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallPage(room: room, video: video),
    ),
  );

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late final CallMedia _media;
  late final ActiveCall _call;
  late final CallRecord _record;
  late final DateTime _startedAt;
  bool _muted = false;
  late bool _camera;

  @override
  void initState() {
    super.initState();
    _camera = widget.video;
    _startedAt = DateTime.now();
    _media = CallMedia();

    // Everything the recording needs is captured HERE, while the screen is
    // alive: the analytics service, the room, the learner's languages. The call
    // ends when the user closes this screen, so anything read later would be
    // read from a context that has already gone.
    final matrix = Matrix.of(context);
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
      sendEvent: (content) =>
          room.sendEvent(content, type: PangeaEventTypes.call),
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
    _call.start(room, video: widget.video);
  }

  void _onCallChanged() {
    if (!mounted) return;
    setState(() {});
    // A call that ended or failed has nothing left to show. Closing here rather
    // than leaving a dead screen up means the user never has to dismiss a call
    // that is already over.
    if (_call.stage == CallStage.ended || _call.stage == CallStage.failed) {
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
  /// **In that order.** Hanging up is what flushes the last chunk of audio and
  /// waits for it to be transcribed; writing the call first would anchor
  /// whatever had arrived so far and mark it done, silently losing the end of
  /// what the learner said.
  ///
  /// `hangUp` is idempotent and returns the same teardown either way, so calling
  /// this from both the ended listener and disposal waits on one teardown and
  /// writes once. Deliberately not awaited and not tied to this widget — it
  /// outlives the screen, which is closing.
  void _finishRecording() => unawaited(
    _call.hangUp().then(
      (_) => _record.finish(
        duration: DateTime.now().difference(_startedAt),
        video: widget.video,
      ),
    ),
  );

  Future<void> _toggleMute() async {
    final next = !_muted;
    await _media.setMicrophoneEnabled(!next);
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _toggleCamera() async {
    final next = !_camera;
    await _media.setCameraEnabled(next);
    if (mounted) setState(() => _camera = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.room.getLocalizedDisplayname()),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.callHangUp,
          onPressed: () => _call.hangUp(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: Center(child: _stageBody(l10n))),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                l10n.callRecordingNotice,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
            _controls(l10n),
          ],
        ),
      ),
    );
  }

  Widget _stageBody(L10n l10n) {
    switch (_call.stage) {
      case CallStage.connecting:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.callConnecting),
          ],
        );
      case CallStage.connected:
        return _participants();
      case CallStage.failed:
        return Text(l10n.callFailed);
      case CallStage.ended:
        return Text(l10n.callEnded);
    }
  }

  /// Every published video track in the call, this device's included.
  ///
  /// Audio needs no widget — LiveKit plays remote audio itself — so a voice call
  /// renders an empty grid, and that is correct rather than a missing case.
  Widget _participants() {
    final tracks = <lk.VideoTrack>[
      ...?_media.room.localParticipant?.videoTrackPublications
          .map((p) => p.track)
          .whereType<lk.VideoTrack>(),
      ..._media.room.remoteParticipants.values
          .expand((p) => p.videoTrackPublications)
          .map((p) => p.track)
          .whereType<lk.VideoTrack>(),
    ];

    if (tracks.isEmpty) return const Icon(Icons.call, size: 64);

    return GridView.count(
      crossAxisCount: tracks.length > 1 ? 2 : 1,
      children: [for (final track in tracks) lk.VideoTrackRenderer(track)],
    );
  }

  Widget _controls(L10n l10n) => Padding(
    padding: const EdgeInsets.only(bottom: 24, top: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton.filledTonal(
          icon: Icon(_muted ? Icons.mic_off : Icons.mic),
          tooltip: _muted ? l10n.callUnmute : l10n.callMute,
          onPressed: _call.stage == CallStage.connected ? _toggleMute : null,
        ),
        IconButton.filled(
          icon: const Icon(Icons.call_end),
          tooltip: l10n.callHangUp,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => _call.hangUp(),
        ),
        IconButton.filledTonal(
          icon: Icon(_camera ? Icons.videocam : Icons.videocam_off),
          tooltip: _camera ? l10n.callCameraOff : l10n.callCameraOn,
          onPressed: _call.stage == CallStage.connected ? _toggleCamera : null,
        ),
      ],
    ),
  );
}
