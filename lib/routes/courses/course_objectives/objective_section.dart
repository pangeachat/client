import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/activity_carousel.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// One Mission of the full course plan: its can-do statement and star count
/// above the row of activities that satisfy it. The row itself is the shared
/// [ActivityCarousel]; this widget owns only the Mission header and the order
/// the Mission's activities are drawn in (smallest party first).
class ObjectiveSection extends StatefulWidget {
  final QuestObjectiveGroup group;
  final void Function(QuestActivity) onTap;
  final int Function(String) userStarsByActivity;
  final bool Function(String activityId)? hasCompletedActivity;

  /// The activity's live map-pin state (colour fill + banner) and "Open (N)"
  /// count, resolved by the parent which holds the course room. See
  /// [CourseObjectivesList].
  final ({
    ActivityPinState? state,
    int openSessions,
    List<String> participants,
    int openSlots,
  })
  Function(String activityId)
  liveStateByActivity;

  /// Course members available to fill activity roles (start-page invite math),
  /// or null until it loads. An activity needing more than this — and not
  /// already live — renders dimmed. See [CourseObjectivesList].
  final int? availableParticipants;
  final double spacing;
  final double? cardWidth;
  final double? cardHeight;

  /// The Mission's rollup from the shared resolver, or null when there is
  /// nothing to show (preview, or the rollup hasn't resolved yet).
  final MissionProgress? progress;

  /// The activity a course ping pointed at, when it lives in this section —
  /// its card gets the bell badge (#8319). Null everywhere else.
  final String? pingedActivityId;

  /// Tapping the Mission header collapses/expands its activity carousel
  /// (expanded by default). On for the full course plan (#8357); off for
  /// plan previews.
  final bool collapsible;

  /// Accent the header as the learner's "Up next" Mission — the shared
  /// resolver's anchor (#8357).
  final bool isUpNext;

  const ObjectiveSection({
    super.key,
    required this.group,
    required this.onTap,
    required this.userStarsByActivity,
    required this.hasCompletedActivity,
    required this.liveStateByActivity,
    required this.availableParticipants,
    required this.progress,
    this.pingedActivityId,
    this.collapsible = false,
    this.isUpNext = false,
    this.spacing = 16.0,
    this.cardWidth,
    this.cardHeight,
  });

  @override
  ObjectiveSectionState createState() => ObjectiveSectionState();
}

class ObjectiveSectionState extends State<ObjectiveSection> {
  /// Missions render expanded; a [ObjectiveSection.collapsible] header tap
  /// folds the carousel to just the header row (#8357).
  bool _collapsed = false;

  bool get _isColumnMode => FluffyThemes.isColumnMode(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final statement = Text(
      widget.group.objective.objective,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: widget.isUpNext ? theme.colorScheme.primary : null,
      ),
    );
    final starFraction = widget.progress == null
        ? null
        : Semantics(
            label: L10n.of(context).starsEarnedOfTotal(
              widget.progress!.stars,
              widget.progress!.threshold,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star,
                  size: 18.0,
                  color: AppConfig.goldByTheme(context),
                ),
                const SizedBox(width: 4.0),
                ExcludeSemantics(
                  child: Text(
                    // Raw stars over the satisfaction threshold — surplus
                    // shows (12/7); only the quest header caps.
                    '${widget.progress!.stars}/${widget.progress!.threshold}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
    final collapseChevron = widget.collapsible
        ? AnimatedRotation(
            turns: _collapsed ? -0.25 : 0,
            duration: FluffyThemes.animationDuration,
            child: const Icon(Icons.expand_more, size: 20.0),
          )
        : null;

    final activities = widget.group.activities;
    activities.sort(
      (a, b) => a.plan.req.numberOfParticipants.compareTo(
        b.plan.req.numberOfParticipants,
      ),
    );

    return Semantics(
      label: L10n.of(context).objective,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Objective header, left to right: the collapse chevron (full plan
          // only), the Mission's earned/threshold stars when the shared
          // rollup is in, then the can-do statement. The Up-next Mission's
          // statement wears the accent.
          Semantics(
            // Without an explicit button container the toggle flattens into
            // the section's group semantics and is unreachable on web, where
            // clicks route through the semantics DOM.
            button: widget.collapsible,
            container: widget.collapsible,
            expanded: widget.collapsible ? !_collapsed : null,
            child: InkWell(
              onTap: widget.collapsible
                  ? () => setState(() => _collapsed = !_collapsed)
                  : null,
              borderRadius: BorderRadius.circular(8.0),
              // The star fraction leads and the collapse chevron trails. In
              // column mode the row has room for the statement between them;
              // on narrow screens the statement drops to its own full-width
              // row so a wrapped statement never shares lines with the icons.
              child: _isColumnMode
                  ? Row(
                      children: [
                        if (starFraction != null) ...[
                          starFraction,
                          const SizedBox(width: 8.0),
                        ],
                        Expanded(child: statement),
                        if (collapseChevron != null) ...[
                          const SizedBox(width: 4.0),
                          collapseChevron,
                        ],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (collapseChevron != null || starFraction != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Row(
                              children: [
                                ?starFraction,
                                const Spacer(),
                                ?collapseChevron,
                              ],
                            ),
                          ),
                        statement,
                      ],
                    ),
            ),
          ),
          // No per-Mission progress bar — only the overall course has a bar (in
          // the header). A Mission shows just its star count above (#7597).
          if (!_collapsed) const SizedBox(height: 12.0),
          // The activities that satisfy this objective.
          if (!_collapsed)
            ActivityCarousel(
              activities: activities,
              onTap: widget.onTap,
              userStarsByActivity: widget.userStarsByActivity,
              hasCompletedActivity: widget.hasCompletedActivity,
              liveStateByActivity: widget.liveStateByActivity,
              availableParticipants: widget.availableParticipants,
              pingedActivityId: widget.pingedActivityId,
              spacing: widget.spacing,
              cardWidth: widget.cardWidth,
              cardHeight: widget.cardHeight,
            ),
        ],
      ),
    );
  }
}
