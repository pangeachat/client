import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goals_dropdown.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_play_badge.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_participant_list.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_state_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_video_player.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_youtube_player.dart';
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
/// A non-playable (image) lead, or an activity with no media, renders as before:
/// the poster/placeholder with the cards over it and no play affordance.
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
  /// True once the learner taps play: the inline player is mounted and the
  /// overlays fade out. The close control resets it back to the poster.
  bool _playing = false;

  static const _fadeDuration = Duration(milliseconds: 250);
  static const _bgHeight = 375.0;

  ActivitySessionStartState get _controller => widget.controller;
  ActivitySessionStateController get _session => widget.sessionController;
  ActivityPlanModel get _activity => widget.activity;
  ActivityMediaBlock? get _hero => _activity.visibleHeroBlock;

  void _play() => setState(() => _playing = true);
  void _stop() => setState(() => _playing = false);

  /// Fades [child] out (and back) as [_playing] toggles, and stops it capturing
  /// taps while faded so the player underneath stays interactive.
  Widget _overlay(Widget child) => AnimatedOpacity(
    opacity: _playing ? 0.0 : 1.0,
    duration: _fadeDuration,
    child: IgnorePointer(ignoring: _playing, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        // Background: the inline player while playing, else the poster (with a
        // play badge when the lead block is a video/YouTube clip).
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _bgHeight,
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _background(theme, constraints.maxWidth),
          ),
        ),
        // Gradient bridge from the image into the page — an overlay, so it fades
        // with the cards and doesn't tint the video or hide its controls.
        Positioned.fill(
          top: 250.0,
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
            padding: const EdgeInsets.only(top: 250.0),
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
        if (_playing)
          Positioned(
            top: 8.0,
            right: 8.0,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              clipBehavior: Clip.hardEdge,
              child: IconButton(
                tooltip: L10n.of(context).close,
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _stop,
              ),
            ),
          ),
      ],
    );
  }

  Widget _background(ThemeData theme, double width) {
    final hero = _hero;
    if (_playing && hero != null) {
      final player = hero.isYoutube
          ? ActivityYoutubePlayer(url: hero.url ?? '')
          : ActivityVideoPlayer(url: hero.resolvedUrl ?? '', autoPlay: true);
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(aspectRatio: 16 / 9, child: player),
        ),
      );
    }

    final poster = ImageByUrl(
      imageUrl: _activity.heroDisplayUrl,
      borderRadius: BorderRadius.zero,
      width: width,
      replacement: Container(
        width: width,
        height: 350.0,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surface,
            ],
          ),
        ),
      ),
    );

    if (!_activity.heroIsPlayable) return poster;

    // Tap the poster (or the badge) to play in place. The badge sits above the
    // role cards (they start 250px down), so it stays reachable.
    return GestureDetector(
      onTap: _play,
      child: Stack(
        alignment: Alignment.center,
        children: [poster, const ActivityMediaPlayBadge(size: 56.0)],
      ),
    );
  }
}
