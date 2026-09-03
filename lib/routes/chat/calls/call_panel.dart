import 'dart:ui' as ui show SemanticsHitTestBehavior;

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

    // Opaque for the same reason the minimized bar is (#8681): the panel
    // covers the app in fullscreen and the chat underneath it in the pane, and
    // its dark Material publishes no semantics node of its own -- so on web
    // with the semantics tree on, every node it covers stayed clickable
    // straight through it. Only its own controls should be reachable while it
    // is up, and they are its children, which keep their clicks.
    return Semantics(
      container: true,
      hitTestBehavior: ui.SemanticsHitTestBehavior.opaque,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (session.showingSummary) return _summary(context, l10n, theme);
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
                            l10n.callTranscriptSharedNotice,
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
      ),
    );
  }

  /// The moment after: who it was, that it ended, and how long it lasted.
  ///
  /// Held for three seconds (or an X) before the panel goes -- a call that
  /// vanishes the instant it ends reads as a drop, and the duration is the
  /// one fact the learner looks for.
  ///
  /// The number is [CallSession.callDuration]: the same clock the timer on
  /// screen was counting, frozen at the moment the call ended, so the figure
  /// the learner watched reach 1:08 is the figure they are shown a second
  /// later. Deliberately NOT the segmented talk time the card and the
  /// analytics use -- that restarts at zero after a rejoin -- so this and the
  /// card can differ for one call, by whatever the peer spent vanished inside
  /// the grace window. Two numbers, each right for what it measures, and this
  /// is the one the learner just watched.
  Widget _summary(BuildContext context, L10n l10n, ThemeData theme) {
    final peer = session.peer;
    final name =
        peer?.calcDisplayname() ?? session.room.getLocalizedDisplayname();
    return Material(
      color: const Color(0xFF14131A),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _voiceBackdrop(theme),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: _OverlayFreeIconButton(
                    label: l10n.close,
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: session.dismissSummary,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Avatar(
                            mxContent: peer?.avatarUrl,
                            name: name,
                            size: 108,
                            showPresence: false,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            name,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            l10n.callEnded,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            formatCallDuration(session.callDuration),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
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

  /// Minimize on the left, fullscreen on the right — and neither is hang up:
  /// resizing the call must never be the thing that ends it.
  Widget _topBar(L10n l10n) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _OverlayFreeIconButton(
        label: l10n.callMinimize,
        icon: const Icon(Icons.expand_more, color: Colors.white),
        onPressed: session.minimize,
      ),
      _OverlayFreeIconButton(
        label: session.fullscreen
            ? l10n.callExitFullscreen
            : l10n.callFullscreen,
        icon: Icon(
          session.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
          color: Colors.white,
        ),
        onPressed: session.toggleFullscreen,
      ),
    ],
  );

  Widget _peerPanel(BuildContext context, L10n l10n, ThemeData theme) {
    final peer = session.peer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Avatar(
              mxContent: peer?.avatarUrl,
              name:
                  peer?.calcDisplayname() ??
                  session.room.getLocalizedDisplayname(),
              size: 108,
              showPresence: false,
            ),
            if (session.peerMuted)
              Positioned(right: -2, bottom: -2, child: _MuteBadge()),
          ],
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
      if (session.peerMuted)
        const Positioned(left: 14, top: 72, child: _MuteBadge()),
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
  // A call that is OVER outranks anything it was doing on the way out. The
  // reconnecting flags used to be read first, so a call that ended while a
  // peer's grace was open still read "reconnecting" -- on a phone, minutes
  // after the other side hung up, which is the same false promise the grace
  // itself was fixed for.
  switch (session.stage) {
    case CallStage.ended:
      return l10n.callEnded;
    case CallStage.declined:
      if (session.peerWasBusy) {
        return l10n.callPeerBusy(session.peer?.calcDisplayname() ?? l10n.user);
      }
      return l10n.callDeclinedByPeer;
    case CallStage.failed:
      return callFailureLine(l10n, session.error);
    case CallStage.connecting:
    case CallStage.connected:
      break;
  }
  // Above the ordinary lines, because it is the one thing on this screen the
  // learner cannot discover for themselves: the call looks completely normal
  // to them while the other person hears silence.
  if (session.microphoneRefused) return l10n.callNoMicrophone;
  if (session.isReconnecting) return l10n.callReconnecting;
  if (session.peerReconnecting) {
    return l10n.callPeerReconnecting(
      session.peer?.calcDisplayname() ?? l10n.user,
    );
  }
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
      if (session.peerWasBusy) {
        return l10n.callPeerBusy(session.peer?.calcDisplayname() ?? l10n.user);
      }
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
  // The CALL's clock, counted from when it began -- which a rejoined session
  // carries over, so both people read the same number instead of one of them
  // restarting at zero after a refresh. Deliberately NOT talkDuration: that
  // is the segmented time anyone could actually be heard, which is the right
  // answer for the card and the analytics and the wrong one for a timer that
  // is supposed to match the other person's screen.
  //
  // Not clamped here. This used to guard its own subtraction and nothing
  // else, which left the line above -- the fallback taken whenever nobody has
  // arrived yet -- unguarded, and it is the same wall clock underneath. The
  // clamp belongs to the formatter, which is the thing that cannot express a
  // negative, and which both this and the ended-call summary go through.
  final began = session.callStartedAt;
  if (began == null) return session.talkDuration;
  return DateTime.now().difference(began);
}

/// `M:SS`, or `H:MM:SS` past an hour.
///
/// Nothing shorter than no time. The arithmetic below cannot express a
/// negative -- Dart's modulo is never negative, so one second short of nothing
/// formats as "0:59" and a minute short as "59:00", both perfectly plausible
/// durations on a screen whose whole job is to state how long the call was.
/// The clamp lives here, with the assumption, rather than at the call sites:
/// the live timer remembered it and the ended-call summary did not, and the
/// summary is the surface a learner actually reads the number off.
String formatCallDuration(Duration d) {
  final seconds = d.isNegative ? 0 : d.inSeconds;
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
      // The tile floats over the app, so it has to WIN the clicks it covers.
      // On web with the semantics tree on (staging forces it via
      // ENABLE_SEMANTICS) a click is dispatched by the `flt-semantics` DOM
      // element under the cursor, not by Flutter's hit test -- and without
      // this the InkWell below is not a container boundary, so the engine
      // parents the whole page underneath it. Its node then blankets the
      // viewport while every page node nested inside it sits ON TOP: a tap on
      // the tile opened whatever button it covered (#8681, the Courses
      // panel's add-course icons), and a tap anywhere else on the page
      // expanded the call. `container` splits the tile back out into its own
      // node, and `opaque` is what earns it `pointer-events: all` and a
      // z-index above its earlier-painted siblings -- the same tool
      // `ModalRoute` uses, and the same fix as #8181 and #7803. The tile's own
      // mute and hang-up buttons are children of this node, so they keep
      // their clicks.
      builder: (context, _) => Semantics(
        container: true,
        hitTestBehavior: ui.SemanticsHitTestBehavior.opaque,
        child: DecoratedBox(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
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
                      // a11y-ignore: the name is on the Semantics above. This
                      // tile also renders from GlobalCallTile, which sits above
                      // the router and so has no Overlay ancestor -- a Tooltip
                      // there throws, and one in the banner stopped calls being
                      // answered at all.
                      child: IconButton(
                        // a11y-ignore: named by the Semantics above
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
                      // a11y-ignore: as above -- named by the Semantics, and no
                      // Overlay above the router for a Tooltip to use.
                      child: IconButton(
                        // a11y-ignore: named by the Semantics above
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
        // Labelled on the CONTROL, not only beside it. The caption below is a
        // separate widget, so without this the button itself reaches a screen
        // reader unnamed -- and an end-to-end test can only find it by pixel
        // position, which is what made the call harness silently useless once
        // the layout moved.
        Semantics(
          button: true,
          enabled: !disabled,
          label: label,
          child: Opacity(
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

/// The corner statement that the other person cannot be heard.
///
/// The standard badge every calling product shows; without it, a muted peer
/// is indistinguishable from a broken connection, and the learner talks into
/// a silence they cannot explain.
class _MuteBadge extends StatelessWidget {
  const _MuteBadge();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Semantics(
      label: l10n.callPeerMuted,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic_off, size: 18, color: Colors.white),
      ),
    );
  }
}

/// An icon button whose accessible name is a Semantics label, not a Tooltip.
///
/// In fullscreen the global call tile renders [CallPanel] above the router,
/// where nothing has an Overlay ancestor. A Tooltip is an OverlayPortal, so
/// `IconButton(tooltip:)` there threw "No Overlay widget found" on every
/// rebuild and the button rendered as an error box -- a learner in fullscreen
/// had no minimize or exit-fullscreen control (#8779). Same rule the banner
/// and [CallMiniTile] already keep.
class _OverlayFreeIconButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  const _OverlayFreeIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: IconButton(
      // a11y-ignore: named by the Semantics above -- no Overlay above the
      // router for a Tooltip to render into.
      icon: icon,
      onPressed: onPressed,
    ),
  );
}
