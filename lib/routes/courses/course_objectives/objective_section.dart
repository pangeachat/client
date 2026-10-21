import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/activity_carousel.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_pacing.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_circle.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_progress_circles.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// One Mission of the full course plan: its can-do statement and star count
/// above the row of activities that satisfy it. The row itself is the shared
/// [ActivityCarousel]; this widget owns only the Mission header and the order
/// the Mission's activities are drawn in (smallest party first).
class ObjectiveSection extends StatelessWidget {
  final QuestObjectiveGroup group;
  final void Function(QuestActivity) onTap;
  final int Function(String) xpByActivity;

  /// The activity's live map-pin state (frame + pill) and its open sessions,
  /// resolved by the parent which holds the course room. See
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

  /// Whether the activity carousel is folded away, leaving just the header.
  final bool collapsed;

  /// Tapping the Mission header calls this to flip [collapsed]; null makes
  /// the header inert. Set for the full course plan (#8357), null for plan
  /// previews. The parent holds the state because the plan is a lazy list: a
  /// section scrolled off screen is disposed, and a flag it owned would come
  /// back expanded (#9248).
  final VoidCallback? onToggleCollapsed;

  /// Accent the header as the learner's current Mission — the shared
  /// resolver's anchor (#8357), labelled "Current mission" (#9559).
  final bool isUpNext;

  /// The Mission the teacher's due dates say the class is on now — the same
  /// "Class location" the circles mark (#9559). It can be the current
  /// Mission too; then the two badges sit side by side.
  final bool isClassLocation;

  /// The Mission's 1-based place in the plan, for its circle's number.
  final int index;

  /// How many Missions the plan has, for the circle's "Mission N of M".
  final int missionCount;

  /// Passed through to [ActivityCarousel.interactive].
  final bool interactive;

  const ObjectiveSection({
    super.key,
    required this.group,
    required this.onTap,
    required this.xpByActivity,
    required this.liveStateByActivity,
    required this.availableParticipants,
    required this.progress,
    this.pingedActivityId,
    this.collapsed = false,
    this.onToggleCollapsed,
    this.isUpNext = false,
    this.isClassLocation = false,
    required this.index,
    required this.missionCount,
    this.spacing = 16.0,
    this.cardWidth,
    this.cardHeight,
    this.interactive = true,
  });

  bool get _collapsible => onToggleCollapsed != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Three header states (#8874): the current Mission wears a "Current
    // mission" label and the primary accent; a satisfied Mission's circle
    // turns to its gold star and its text mutes; the rest stay plain. The
    // first two are mutually exclusive: the anchor is unsatisfied by
    // definition, and a course whose every Mission is satisfied has no anchor
    // at all (#8997).
    final satisfied = progress?.satisfied ?? false;
    final headerColor = isUpNext
        ? theme.colorScheme.primary
        : satisfied
        ? theme.colorScheme.onSurfaceVariant
        : null;

    // The Mission's circle from the course page's row (#9559): its number,
    // or its star once complete, inside the gold ring of its XP — in place
    // of the old star and XP count. The XP is in its accessible name.
    final circle = Semantics(
      label: progress == null
          ? null
          : L10n.of(
              context,
            ).xpTowardObjective(progress!.xp, progress!.threshold),
      child: ExcludeSemantics(
        child: ObjectiveCircle(
          item: ObjectiveCircleData(
            index: index,
            statement: group.objective.objective,
            state: satisfied
                ? ObjectiveCircleState.complete
                : isUpNext
                ? ObjectiveCircleState.current
                : ObjectiveCircleState.later,
            progress: progress?.fraction ?? 0.0,
            xp: progress,
          ),
          count: missionCount,
          showSelectedLabel: false,
          showClassStrip: false,
          showPointer: false,
          onTap: null,
        ),
      ),
    );
    // The can-do, then its labels after its text so they never push it
    // over: the current Mission, and where the class is by the teacher's
    // due dates — the emphasis in words, so it is never colour alone.
    final statement = Text.rich(
      TextSpan(
        text: group.objective.objective,
        children: [
          if (isUpNext)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _SectionBadge(
                label: L10n.of(context).currentMission,
                fill: theme.colorScheme.primary,
                ink: theme.colorScheme.onPrimary,
              ),
            ),
          if (isClassLocation)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _SectionBadge(
                label: L10n.of(context).classLocation,
                fill: theme.colorScheme.outlineVariant,
                ink: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: headerColor,
        fontWeight: isUpNext ? FontWeight.w500 : null,
      ),
    );
    // The course's own soft due date (content-studio) as a chip under the
    // title, so it reads at a glance down the plan and stays when the Mission
    // is folded. The date stays after it passes; nothing is blocked or marked.
    final pacing = group.pacing;
    final dueAt = pacing?.dueAt;
    final dueChip = dueAt == null
        ? null
        : MissionDueChip(dueAt: dueAt, timeZone: pacing?.timeZone);
    // The teacher's note under the date; folded away with the activities.
    final note = pacing?.note;
    final noteLine = collapsed || note == null || note.isEmpty
        ? null
        : MissionNoteLine(note: note);
    final pacingLines = dueChip == null && noteLine == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4.0,
              children: [?dueChip, ?noteLine],
            ),
          );
    final collapseChevron = _collapsible
        ? AnimatedRotation(
            turns: collapsed ? -0.25 : 0,
            duration: FluffyThemes.animationDuration,
            child: const Icon(Icons.expand_more, size: 20.0),
          )
        : null;

    // Sorted as a copy: the group's list can be the shared outline cache's.
    final activities = [...group.activities]
      ..sort(
        (a, b) => a.plan.req.numberOfParticipants.compareTo(
          b.plan.req.numberOfParticipants,
        ),
      );

    return Semantics(
      label: L10n.of(context).objective,
      container: true,
      // The emphasis lives in the header only. A band or an outline around the
      // whole section was tried and dropped: a tint shows the carousel's
      // surface-coloured scroll-arrow strip as a notch, and any inset throws
      // this section's margins off against its neighbours (#8874).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Objective header, left to right: the Mission's circle, the can-do
          // statement with its labels after it, then the collapse chevron
          // (full plan only).
          Semantics(
            // Without an explicit button container the toggle flattens into
            // the section's group semantics and is unreachable on web, where
            // clicks route through the semantics DOM.
            button: _collapsible,
            container: _collapsible,
            expanded: _collapsible ? !collapsed : null,
            child: InkWell(
              onTap: onToggleCollapsed,
              borderRadius: BorderRadius.circular(8.0),
              // The circle leads, the statement (with its labels) fills the
              // middle and wraps there, and the collapse chevron trails.
              child: Row(
                children: [
                  circle,
                  const SizedBox(width: 10.0),
                  Expanded(child: statement),
                  if (collapseChevron != null) ...[
                    const SizedBox(width: 4.0),
                    collapseChevron,
                  ],
                ],
              ),
            ),
          ),
          ?pacingLines,
          // No per-Mission progress bar: the circle's ring is the Mission's
          // progress (#9559).
          if (!collapsed) const SizedBox(height: 12.0),
          // The activities that satisfy this objective.
          if (!collapsed)
            ActivityCarousel(
              activities: activities,
              onTap: onTap,
              xpByActivity: xpByActivity,
              liveStateByActivity: liveStateByActivity,
              availableParticipants: availableParticipants,
              pingedActivityId: pingedActivityId,
              spacing: spacing,
              cardWidth: cardWidth,
              cardHeight: cardHeight,
              interactive: interactive,
            ),
        ],
      ),
    );
  }
}

/// One of a Mission header's labels in the full plan: "Current mission" or
/// "Class location" (#9559).
class _SectionBadge extends StatelessWidget {
  final String label;
  final Color fill;
  final Color ink;

  const _SectionBadge({
    required this.label,
    required this.fill,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsetsDirectional.only(start: 6.0),
    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(8.0),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: ink, fontWeight: FontWeight.w600),
    ),
  );
}
