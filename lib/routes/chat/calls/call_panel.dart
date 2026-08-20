import 'package:flutter/material.dart';

import 'package:livekit_client/livekit_client.dart' as lk;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_session.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// The call, rendered INSIDE the chat panel it belongs to.
///
/// A call is not a route and not a full-screen takeover: it lives in the same
/// right-hand pane as its conversation, can be minimized to a slim tile at the
/// top of that pane, and the user keeps reading and typing underneath. This is
/// a view of [CallSession] and nothing more — mounting or unmounting it never
/// touches the call itself.
class CallPanel extends StatelessWidget {
  final CallSession session;

  const CallPanel({required this.session, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final tracks = session.videoTracks();
        return Material(
          // Its own dark surface: every calling product darkens the call
          // area, and a flat container colour reads as an unfinished page.
          color: const Color(0xFF14131A),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (tracks.isNotEmpty)
                _videoLayer(tracks)
              else
                _voiceBackdrop(theme),
              SafeArea(
                child: Column(
                  children: [
                    _topBar(l10n),
                    Expanded(
                      child: tracks.isNotEmpty
                          ? const SizedBox.shrink()
                          // Scrollable so a short pane shrinks the panel
                          // rather than pushing the controls off the bottom.
                          : Center(
                              child: SingleChildScrollView(
                                child: _peerPanel(context, l10n, theme),
                              ),
                            ),
                    ),
                    if (tracks.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          callStatusLine(l10n, session),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    if (!session.isFailed)
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
                    if (session.isFailed)
                      _failedControls(l10n)
                    else
                      _controls(l10n),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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

  /// Minimize, not hang up: shrinking the call must never be the thing that
  /// ends it.
  Widget _topBar(L10n l10n) => Align(
    alignment: Alignment.centerLeft,
    child: Semantics(
      label: l10n.callMinimize,
      button: true,
      child: IconButton(
        icon: const Icon(Icons.expand_more, color: Colors.white),
        onPressed: session.minimize,
      ),
    ),
  );

  Widget _peerPanel(BuildContext context, L10n l10n, ThemeData theme) {
    final peer = session.peer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Avatar(
          mxContent: peer?.avatarUrl,
          name:
              peer?.calcDisplayname() ?? session.room.getLocalizedDisplayname(),
          size: 108,
          showPresence: false,
        ),
        const SizedBox(height: 20),
        Text(
          peer?.calcDisplayname() ?? session.room.getLocalizedDisplayname(),
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
          callStatusLine(l10n, session),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  /// The peer full-bleed with this device inset — the layout every video call
  /// uses.
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
    final live =
        session.stage == CallStage.connected && !session.isReconnecting;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28, top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CallButton(
            icon: session.muted ? Icons.mic_off : Icons.mic,
            label: session.muted ? l10n.callUnmute : l10n.callMute,
            background: Colors.white.withValues(alpha: 0.14),
            foreground: Colors.white,
            onPressed: live ? session.toggleMute : null,
          ),
          const SizedBox(width: 22),
          _CallButton(
            icon: Icons.call_end,
            label: l10n.callHangUp,
            background: const Color(0xFFD32F2F),
            foreground: Colors.white,
            large: true,
            onPressed: session.endCall,
          ),
          const SizedBox(width: 22),
          _CallButton(
            icon: session.cameraOn ? Icons.videocam : Icons.videocam_off,
            label: session.cameraOn ? l10n.callCameraOff : l10n.callCameraOn,
            background: Colors.white.withValues(alpha: 0.14),
            foreground: Colors.white,
            onPressed: live ? session.toggleCamera : null,
          ),
        ],
      ),
    );
  }

  /// A failed call keeps its screen — vanishing on failure is what makes an
  /// error indistinguishable from a crash — until the user dismisses it.
  Widget _failedControls(L10n l10n) => Padding(
    padding: const EdgeInsets.only(bottom: 28, top: 16),
    child: _CallButton(
      icon: Icons.close,
      label: l10n.close,
      background: Colors.white.withValues(alpha: 0.14),
      foreground: Colors.white,
      onPressed: session.dismissFailed,
    ),
  );
}

/// One line saying what the call is doing. Shared by the panel and both tiles
/// so no two surfaces can disagree about the same call.
String callStatusLine(L10n l10n, CallSession session) {
  if (session.isFailed) return callFailureLine(l10n, session.error);
  if (session.isReconnecting) return l10n.callReconnecting;
  switch (session.stage) {
    case CallStage.connecting:
      return session.placedCall ? l10n.callRinging : l10n.callConnecting;
    case CallStage.connected:
      if (!session.hadPeer) return l10n.callRinging;
      return formatCallDuration(_elapsed(session));
    case CallStage.failed:
      return callFailureLine(l10n, session.error);
    case CallStage.ended:
      return l10n.callEnded;
    case CallStage.declined:
      return l10n.callDeclinedByPeer;
  }
}

/// What went wrong, specifically. One generic string for every failure made
/// no-focus, a refused token, an unreachable SFU and being already in a call
/// all indistinguishable — undiagnosable in the field and unhelpful on screen.
String callFailureLine(L10n l10n, Object? error) {
  if (error is AlreadyInACall) return l10n.callFailedBusy;
  if (error is CallTokenException) {
    return l10n.callFailedService;
  }
  if (error is StateError && error.message.contains('focus')) {
    return l10n.callFailedNoFocus;
  }
  return l10n.callFailed;
}

Duration _elapsed(CallSession session) {
  final since = session.talkStartedAt;
  if (since == null) return Duration.zero;
  return DateTime.now().difference(since);
}

/// `M:SS`, or `H:MM:SS` past an hour.
String formatCallDuration(Duration d) {
  final seconds = d.inSeconds;
  final s = (seconds % 60).toString().padLeft(2, '0');
  final m = (seconds ~/ 60) % 60;
  final h = seconds ~/ 3600;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
  return '$m:$s';
}

/// The minimized call: a slim tile with the essentials — who, how long, mute,
/// hang up — and a tap anywhere else to expand. Docked at the top of the chat
/// pane while its room is open; floating (via the global host) when the user
/// has navigated elsewhere.
class CallMiniTile extends StatelessWidget {
  final CallSession session;

  /// What tapping the tile body does — expand in place (in the chat) or
  /// navigate back to the call's room first (global).
  final VoidCallback onOpen;

  const CallMiniTile({required this.session, required this.onOpen, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1D26),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Avatar(
                    mxContent: session.peer?.avatarUrl,
                    name:
                        session.peer?.calcDisplayname() ??
                        session.room.getLocalizedDisplayname(),
                    size: 32,
                    showPresence: false,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          session.peer?.calcDisplayname() ??
                              session.room.getLocalizedDisplayname(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          callStatusLine(l10n, session),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Semantics(
                    label: session.muted ? l10n.callUnmute : l10n.callMute,
                    button: true,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        session.muted ? Icons.mic_off : Icons.mic,
                        size: 20,
                        color: Colors.white,
                      ),
                      onPressed:
                          session.stage == CallStage.connected &&
                              !session.isReconnecting
                          ? session.toggleMute
                          : null,
                    ),
                  ),
                  Semantics(
                    label: l10n.callHangUp,
                    button: true,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.call_end,
                        size: 20,
                        color: Color(0xFFEF5350),
                      ),
                      onPressed: session.isFailed
                          ? session.dismissFailed
                          : session.endCall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
