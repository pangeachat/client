import 'package:flutter/material.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix show Room;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
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
  bool _muted = false;
  late bool _camera;

  @override
  void initState() {
    super.initState();
    _camera = widget.video;
    _media = CallMedia();
    _call = ActiveCall(
      calls: Matrix.of(context).callService,
      media: _media,
      capture: CallCaptureService(sink: const DiscardingSink()),
    )..addListener(_onCallChanged);
    _call.start(widget.room, video: widget.video);
  }

  void _onCallChanged() {
    if (!mounted) return;
    setState(() {});
    // A call that ended or failed has nothing left to show. Closing here rather
    // than leaving a dead screen up means the user never has to dismiss a call
    // that is already over.
    if (_call.stage == CallStage.ended || _call.stage == CallStage.failed) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _call.removeListener(_onCallChanged);
    // ActiveCall.dispose hangs up. Leaving the screen ends the call — there is no
    // background call in v1, and a call still running behind a closed screen is
    // one the user cannot hang up.
    _call.dispose();
    super.dispose();
  }

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

/// Accepts chunks and drops them.
///
/// Capture runs from the first call so the recording path is exercised for real,
/// but transcription is a separate change: sending audio to speech-to-text before
/// the transcript has anywhere to land would spend money to produce nothing.
class DiscardingSink implements CallAudioSink {
  const DiscardingSink();

  @override
  Future<void> deliver(chunk) async {}

  @override
  Future<void> close() async {}
}
