import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_star.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';

/// One can-do as a self-contained unit (#9420): a gold XP ring with the
/// Mission's star inside it, the statement and its XP over the threshold. A
/// tap opens its detail page beside the list, as a word opens from the vocab
/// list; Practice is the detail page's main action (#9559).
class MissionTile extends StatelessWidget {
  final QuestObjectiveGroup group;
  final MissionProgress? progress;
  final MissionXpBreakdown breakdown;

  /// The course this tile's numbers come from, so its detail page shows the
  /// same course (#9559).
  final String courseId;
  final bool selected;

  const MissionTile({
    required this.group,
    required this.progress,
    required this.breakdown,
    required this.courseId,
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
                courseId: courseId,
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
                          if (progress != null)
                            Text(
                              l10n.xpOfThreshold(
                                progress.xp,
                                progress.threshold,
                              ),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
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
