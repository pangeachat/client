import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goals_dropdown.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_play_badge.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_participant_list.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_video_close_button.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_video_player.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_video_screen.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_youtube_player.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

/// The activity start page's hero: a full-bleed background over which the role
/// cards and goals dropdown float.
///
/// The plan page is a focused surface, so media plays in place (see
/// activities.instructions.md). When the activity's lead media block is a video
/// or YouTube clip, the hero shows that block's poster with a play badge, and
/// tapping it mounts the player inline. While the clip plays, the role cards,
/// gradient, and goals overlay fade out so the player is unobstructed; a close
/// control returns to the poster and restores the overlays.
///
/// Both swaps remove the control that was just pressed. When it was pressed
/// from the keyboard the focus it held moves with the swap — poster to player,
/// close to poster — so the next key lands on what replaced it (#9128).
///
/// That inline path is web/desktop only. On native mobile the plan is a
/// scrolling bottom sheet, which a webview can't live inside (#7672/#7673), so
/// tapping the poster opens the video on its own screen instead — see
/// [openActivityVideo].
///
/// An image lead opens the same way, in place on every platform (there is no
/// webview to escape the sheet): the overlays fade, the image shows whole on
/// the same letterbox, and the close control or a second tap on the image
/// brings the crop and overlays back. The image is one toggle button that
/// keeps keyboard focus as it opens and closes.
///
/// An activity with no visible media renders the poster/placeholder with the
/// cards over it and nothing to open.
///
/// Web note: the YouTube/video player is a platform view (a real DOM
/// `<iframe>`/`<video>`). A Flutter layer composited above it still swallows
/// native mouse events even when [IgnorePointer] excludes it from Flutter's own
/// hit-test — so once faded, the overlays are removed from the tree entirely,
/// and the close control is laid out in its own strip beside (never over) the
/// player. Both keep the embed's own controls clickable. See #7477 follow-up.
class ActivityStartHero extends StatefulWidget {
  final ActivitySessionStartState controller;
  final ActivitySessionStateController sessionController;
  final ActivityPlanModel activity;

  const ActivityStartHero({
    super.key,
    required this.controller,
    required this.sessionController,
    required this.activity,
  });

  @override
  State<ActivityStartHero> createState() => _ActivityStartHeroState();
}

class _ActivityStartHeroState extends State<ActivityStartHero> {
  /// True while the lead media is open — the video playing inline, or the
  /// image shown whole — and the overlays faded out. The close control resets
  /// it back to the poster.
  bool _mediaOpen = false;

  /// Whether the fading overlays (gradient, role cards, goals) are still in the
  /// widget tree. They stay mounted through the fade-out, then leave entirely so
  /// no Flutter layer is left composited over the player's iframe swallowing its
  /// controls (see the class doc). Restored the moment the media is closed.
  bool _overlaysMounted = true;

  /// The hero's height while the media is open: the height it had with the
  /// overlays in place, so the page below doesn't move when they leave.
  double _openHeight = _bgHeight;

  final FocusNode _posterFocus = FocusNode(debugLabel: 'activity hero poster');

  /// Whether the mounting player should claim focus: true when the poster was
  /// pressed while it held keyboard focus.
  bool _playerAutofocus = false;

  static const _fadeDuration = Duration(milliseconds: 250);
  static const _bgHeight = 375.0;

  ActivitySessionStartState get _controller => widget.controller;
  ActivitySessionStateController get _session => widget.sessionController;
  ActivityPlanModel get _activity => widget.activity;
  ActivityMediaBlock? get _hero => _activity.visibleHeroBlock;

  void _openMedia() {
    final hero = _hero;
    // Native mobile: the player is a webview that can't live in the plan's
    // scrolling bottom sheet (it escapes the sheet and its gestures force an
    // inexitable fullscreen — #7672/#7673), so play it on its own screen.
    // Web/desktop play inline below, where a platform view behaves.
    if (hero != null && _activity.heroIsPlayable && PlatformInfos.isMobile) {
      openActivityVideo(
        context,
        hero,
        captionLanguage: _activity.req.targetLanguage,
      );
      return;
    }
    final height = context.size!.height;
    setState(() {
      _playerAutofocus = _posterFocus.hasFocus;
      _openHeight = height;
      _mediaOpen = true;
      _overlaysMounted = true; // kept for the fade-out, dropped by _onFadedOut
    });
  }

  void _closeMedia() {
    final focus = FocusManager.instance.primaryFocus?.context;
    final focusLeavesWithPlayer =
        focus?.findAncestorStateOfType<_ActivityStartHeroState>() == this;
    setState(() {
      _mediaOpen = false;
      _overlaysMounted = true; // bring the overlays back
    });
    if (focusLeavesWithPlayer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _posterFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _posterFocus.dispose();
    super.dispose();
  }

  /// Once the overlays have faded to nothing, unmount them. [IgnorePointer]
  /// keeps them out of Flutter's hit-test, but on web an opacity-0 Flutter layer
  /// left over the player's `<iframe>` still eats the browser's clicks — so the
  /// video's own controls only become usable after this removes the layers.
  void _onFadedOut() {
    if (_mediaOpen && _overlaysMounted) {
      setState(() => _overlaysMounted = false);
    }
  }

  /// Fades [child] out (and back) as [_mediaOpen] toggles, and stops it
  /// capturing taps while faded so the media underneath stays interactive.
  Widget _overlay(Widget child) => AnimatedOpacity(
    opacity: _mediaOpen ? 0.0 : 1.0,
    duration: _fadeDuration,
    onEnd: _onFadedOut,
    child: IgnorePointer(ignoring: _mediaOpen, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        // Background: the opened media while open, else the poster (with a
        // play badge when the lead block is a video/YouTube clip). The opened
        // media carries its own close control, so nothing is stacked above it.
        //
        // Non-positioned, so it anchors the Stack's height in every state. The
        // hero sits in a scroll view (unbounded height), so the Stack sizes to
        // its non-positioned children. While open the overlays are removed and
        // the role cards were the only other non-positioned child; without this
        // anchor the Stack would collapse to zero, unsizing the player and
        // leaving an empty scroll gap below the video (#7490). It anchors at
        // [_openHeight] while open, so the media takes the role cards' space
        // and the text below stays put.
        SizedBox(
          width: double.infinity,
          height: _mediaOpen ? _openHeight : _bgHeight,
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _background(theme, constraints.maxWidth),
          ),
        ),
        // The overlays float over the poster and fade out while the media is
        // open. They are omitted (not merely transparent) once it owns the hero.
        if (_overlaysMounted) ...[
          // Gradient bridge from the image into the page — an overlay, so it
          // fades with the cards and doesn't tint the video or hide its
          // controls.
          Positioned.fill(
            top: 300.0,
            child: _overlay(
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      theme.colorScheme.surface.withAlpha(0),
                      theme.colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_session.showRoleCards)
            Padding(
              padding: const EdgeInsets.only(top: 300.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  constraints: const BoxConstraints(maxWidth: 600.0),
                  child: _overlay(
                    Opacity(
                      opacity: _session.roleCardOpacity,
                      child: ActivityParticipantList(
                        activity: _activity,
                        room: _controller.activityRoom,
                        assignedRoles: _controller.assignedRoles,
                        course: _controller.courseParent,
                        onTap: _session.selectRole,
                        canSelect: _session.canSelectRole,
                        isSelected: _session.isRoleSelected,
                        isShimmering: _session.isRoleShimmering,
                        showStarsCard: _session.showStarsCard,
                        completedGoalsForRole: _session.completedGoalIdsForRole,
                        tutorialTargetId: _controller.activityRolesTargetId,
                        onTutorialTargetMounted:
                            _controller.onTutorialSurfaceChanged,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _overlay(
              ActivityGoalsDropdown(
                goals: _session.selectedRoleGoals,
                completedGoalIds: _session.selectedRoleCompletedGoalIds,
                startCollapsed: _session.goalsStartCollapsed,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The opened media sits on a black letterbox in either theme, under a strip
  /// holding the close control. The strip is never laid over the media: a
  /// Flutter widget composited over the video's platform view doesn't receive
  /// DOM clicks on web, and over an image the white X has no backdrop to hold
  /// contrast.
  Widget _background(ThemeData theme, double width) => ColoredBox(
    color: _mediaOpen ? Colors.black : Colors.transparent,
    child: Column(
      children: [
        if (_mediaOpen)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ActivityVideoCloseButton(onPressed: _closeMedia),
          ),
        Expanded(child: _media(theme, width)),
      ],
    ),
  );

  Widget _media(ThemeData theme, double width) {
    final hero = _hero;
    if (_mediaOpen && hero != null && _activity.heroIsPlayable) {
      final player = hero.isYoutube
          ? ActivityYoutubePlayer(
              url: hero.url ?? '',
              captionLanguage: _activity.req.targetLanguage,
              autofocus: _playerAutofocus,
            )
          : ActivityVideoPlayer(
              url: hero.resolvedUrl ?? '',
              autoPlay: true,
              autofocus: _playerAutofocus,
            );
      return Center(
        child: AspectRatio(aspectRatio: 16 / 9, child: player),
      );
    }

    final poster = ImageByUrl(
      imageUrl: _activity.heroDisplayUrl,
      borderRadius: BorderRadius.zero,
      width: width,
      // Open, the image shows whole instead of the poster's crop.
      fit: _mediaOpen ? BoxFit.contain : BoxFit.cover,
      replacement: Container(
        width: width,
        height: 350.0,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              // The pale brand tint the gradient was designed around;
              // primaryContainer is a vivid fill under fidelity.
              theme.colorScheme.primaryFixed,
              theme.colorScheme.surface,
            ],
          ),
        ),
      ),
    );

    if (hero == null) return poster;

    if (!_activity.heroIsPlayable) {
      return FocusRingTapTarget(
        onTap: _mediaOpen ? _closeMedia : _openMedia,
        focusNode: _posterFocus,
        label: L10n.of(context).viewImageLabel,
        expanded: _mediaOpen,
        shape: const RoundedRectangleBorder(),
        // The ring crosses the image, where no single colour holds 3:1.
        twoToneRing: true,
        child: poster,
      );
    }

    // Tap the poster (or the badge) to play in place. The badge sits above the
    // role cards (they start 250px down), so it stays reachable.
    return FocusRingTapTarget(
      onTap: _openMedia,
      focusNode: _posterFocus,
      label: L10n.of(context).playVideo,
      shape: const RoundedRectangleBorder(),
      // The ring crosses the poster image, where no single colour holds 3:1.
      twoToneRing: true,
      child: Stack(
        alignment: Alignment.center,
        children: [poster, const ActivityMediaPlayBadge(size: 56.0)],
      ),
    );
  }
}
