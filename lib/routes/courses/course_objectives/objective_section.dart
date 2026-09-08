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

    // Three header states (#8874): the Up-next Mission is outlined in primary
    // and says so in words; a satisfied Mission trades its star for a check
    // and mutes its text; the rest stay plain. Up next wins the text colour
    // when both apply (every Mission satisfied → the resolver anchors on the
    // weakest one).
    final satisfied = widget.progress?.satisfied ?? false;
    final headerColor = widget.isUpNext
        ? theme.colorScheme.primary
        : satisfied
        ? theme.colorScheme.onSurfaceVariant
        : null;

    final statement = Text(
      widget.group.objective.objective,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: headerColor,
        fontWeight: widget.isUpNext ? FontWeight.w500 : null,
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
                  satisfied ? Icons.check_circle : Icons.star,
                  size: 18.0,
                  color: satisfied
                      ? AppConfig.successByTheme(context)
                      : AppConfig.goldByTheme(context),
                ),
                const SizedBox(width: 4.0),
                ExcludeSemantics(
                  child: Text(
                    // Raw stars over the satisfaction threshold — surplus
                    // shows (12/7); only the quest header caps.
                    '${widget.progress!.stars}/${widget.progress!.threshold}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: headerColor,
                    ),
                  ),
                ),
              ],
            ),
          );
    // The emphasis in words, so it is never colour alone.
    final upNextLabel = widget.isUpNext
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Text(
              L10n.of(context).upNext,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        : null;
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
      // The Up-next Mission's outline wraps the header AND its activity row,
      // so the whole section reads as "here" when scanning by thumbnails. An
      // outline rather than a fill: the carousel's scroll arrow paints a
      // surface-coloured strip over the row's edge, which reads as a notch cut
      // out of any tinted band.
      child: Container(
        // A 12 px inset like the band had: 10 px of padding inside the 2 px line.
        padding: widget.isUpNext ? const EdgeInsets.all(10.0) : EdgeInsets.zero,
        decoration: widget.isUpNext
            ? BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 2.0,
                ),
                borderRadius: BorderRadius.circular(12.0),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Objective header, left to right: the Mission's earned/threshold
            // stars when the shared rollup is in, the Up-next label when this is
            // the anchor, the can-do statement, then the collapse chevron (full
            // plan only).
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
                          if (upNextLabel != null) ...[
                            upNextLabel,
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
                          if (collapseChevron != null ||
                              starFraction != null ||
                              upNextLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: Row(
                                children: [
                                  ?starFraction,
                                  if (upNextLabel != null) ...[
                                    if (starFraction != null)
                                      const SizedBox(width: 8.0),
                                    upNextLabel,
                                  ],
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
      ),
    );
  }
}
