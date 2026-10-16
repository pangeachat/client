import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/start_practice.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_star.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';

/// One can-do as a self-contained unit (#9420): a gold XP ring
/// with the Mission's star inside it, the statement, its XP over the threshold
/// and how many of its activities the learner has played, and a practice
/// button. A tap opens its detail page beside the list, as a word opens from
/// the vocab list.
class MissionTile extends StatelessWidget {
  final QuestObjectiveGroup group;
  final MissionProgress? progress;
  final MissionXpBreakdown breakdown;
  final List<Room> sessions;
  final bool selected;

  const MissionTile({
    required this.group,
    required this.progress,
    required this.breakdown,
    required this.sessions,
    required this.selected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context);
    final palette = MissionRingPalette.of(context);
    final progress = this.progress;
    final satisfied = progress?.satisfied ?? false;
    final threshold = progress?.threshold ?? 0;
    final played = {for (final room in sessions) room.activityId}.length;
    final radius = BorderRadius.circular(20.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Semantics(
        button: true,
        selected: selected,
        label: [
          group.objective.objective,
          if (progress != null)
            l10n.xpTowardObjective(progress.xp, progress.threshold),
          l10n.objectiveActivityCount(played),
        ].join(', '),
        child: Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2.0 : 1.5,
            ),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: () => context.go(
              WorkspaceNav.openObjectiveDetail(
                GoRouterState.of(context).uri,
                group.objective.id,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 12.0, 4.0, 12.0),
              child: Row(
                spacing: 12.0,
                children: [
                  ExcludeSemantics(
                    child: MissionXpRing(
                      size: 60.0,
                      strokeWidth: 7.0,
                      trackColor: palette.track,
                      gapColor: scheme.surface,
                      segments: palette.segmentsFor(breakdown, threshold),
                      child: MissionStar(satisfied: satisfied, size: 26.0),
                    ),
                  ),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4.0,
                        children: [
                          Text(
                            group.objective.objective,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              if (progress != null)
                                l10n.xpOfThreshold(
                                  progress.xp,
                                  progress.threshold,
                                ),
                              l10n.objectiveActivityCount(played),
                            ].join('  ·  '),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: l10n.practiceObjective,
                    icon: const Icon(Symbols.fitness_center, size: 20.0),
                    onPressed: () => startPractice(
                      context,
                      ConstructTypeEnum.vocab,
                      missionId: group.objective.id,
                    ),
                  ),
                  ExcludeSemantics(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
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
