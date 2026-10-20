import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_star.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';

/// The top of the page: the star and statement, then the XP ring with what's
/// left to the star and where the XP came from — conversation (goals named
/// within it) and practice, the same two golds as every Mission meter — then
/// the same XP by skill (#9559).
class ObjectiveHero extends StatelessWidget {
  final String statement;
  final MissionProgress? progress;
  final MissionXpBreakdown breakdown;

  /// The Mission's XP by the skill it exercised; goals are in none of them.
  final Map<LearningSkillsEnum, int> skillXp;

  const ObjectiveHero({
    required this.statement,
    required this.progress,
    required this.breakdown,
    required this.skillXp,
    super.key,
  });

  /// The four skills, in the order a teacher lists them.
  static const List<LearningSkillsEnum> _skills = [
    LearningSkillsEnum.speaking,
    LearningSkillsEnum.hearing,
    LearningSkillsEnum.writing,
    LearningSkillsEnum.reading,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context);
    final palette = MissionRingPalette.of(context);
    final numbers = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final progress = this.progress;
    final satisfied = progress?.satisfied ?? false;
    final threshold = progress?.threshold ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20.0,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10.0,
          children: [
            MissionStar(satisfied: satisfied, size: 44.0),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  statement,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Semantics(
              label: progress == null
                  ? null
                  : l10n.xpTowardObjective(progress.xp, progress.threshold),
              child: ExcludeSemantics(
                child: MissionXpRing(
                  size: 128.0,
                  strokeWidth: 14.0,
                  trackColor: palette.track,
                  gapColor: scheme.surface,
                  segments: palette.segmentsFor(breakdown, threshold),
                  child: progress == null
                      ? null
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              numbers.format(progress.xp),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                              ),
                            ),
                            Text(
                              l10n.xpThresholdSuffix(progress.threshold),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(width: 20.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10.0,
                children: [
                  if (progress != null)
                    Text(
                      satisfied
                          ? l10n.missionStarEarned
                          : l10n.xpToYourStar(
                              numbers.format(progress.threshold - progress.xp),
                            ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  _LegendLine(
                    color: palette.conversation,
                    label: l10n.xpFromConversation(
                      numbers.format(breakdown.conversation),
                    ),
                    detail: breakdown.goals > 0
                        ? l10n.xpIncludingGoals(numbers.format(breakdown.goals))
                        : null,
                  ),
                  _LegendLine(
                    color: palette.practice,
                    label: l10n.xpFromPractice(
                      numbers.format(breakdown.practice),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10.0,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.xpBySkillTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Row(
              spacing: 8.0,
              children: [
                for (final skill in _skills)
                  Expanded(
                    child: _SkillTile(skill: skill, xp: skillXp[skill] ?? 0),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendLine extends StatelessWidget {
  final Color color;
  final String label;

  /// A quieter line under [label], e.g. how much of it came from goals.
  final String? detail;

  const _LegendLine({required this.color, required this.label, this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detail = this.detail;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8.0,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3.0),
          child: MissionXpSwatch(color: color, size: 12.0),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (detail != null)
                Text(
                  detail,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One skill's XP: its icon, its name and the number, on a quiet tile.
class _SkillTile extends StatelessWidget {
  final LearningSkillsEnum skill;
  final int xp;

  const _SkillTile({required this.skill, required this.xp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context);
    final name = skill.tooltip(context);
    final amount = l10n.xpAmount(xp);
    return Semantics(
      label: '$name, $amount',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.all(Radius.circular(12.0)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 6.0,
              vertical: 10.0,
            ),
            child: Column(
              spacing: 4.0,
              children: [
                Icon(skill.icon, size: 20.0, color: scheme.onSurfaceVariant),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  amount,
                  maxLines: 1,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
