import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_star.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';

/// The top of the page: the star and statement, then the XP ring with what's
/// left to the star and where the XP came from.
class ObjectiveHero extends StatelessWidget {
  final String statement;
  final MissionProgress? progress;
  final MissionXpBreakdown breakdown;

  const ObjectiveHero({
    required this.statement,
    required this.progress,
    required this.breakdown,
    super.key,
  });

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
                  for (final (color, label) in [
                    (
                      palette.chat,
                      l10n.xpFromChats(numbers.format(breakdown.chat)),
                    ),
                    (
                      palette.goals,
                      l10n.xpFromGoals(numbers.format(breakdown.goals)),
                    ),
                    (
                      palette.practice,
                      l10n.xpFromPractice(numbers.format(breakdown.practice)),
                    ),
                  ])
                    Row(
                      spacing: 8.0,
                      children: [
                        Container(
                          width: 12.0,
                          height: 12.0,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.outline),
                          ),
                        ),
                        Text(
                          label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
