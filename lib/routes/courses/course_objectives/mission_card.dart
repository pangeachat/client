import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/bold_tonal_button.dart';
import 'package:fluffychat/pangea/common/widgets/pulsing_glow.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_play_button.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_star.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';

/// The course page's Mission card (#9420): which Mission, its
/// can-do statement, a gold ring of the XP earned toward its star split by
/// where it came from (chats, goals, practice), then Play — the best next
/// thing to do for this Mission — and practice on its words.
class MissionCard extends StatelessWidget {
  final QuestObjectiveGroup group;

  /// 1-based position among the course's Missions, or null when unknown.
  final int? index;

  /// The Mission's XP over its threshold; null before progress resolves (or
  /// in a preview), which draws an empty ring with no count.
  final MissionProgress? progress;
  final MissionXpBreakdown? breakdown;

  /// Null draws Play disabled (no activity to open).
  final VoidCallback? onPlay;

  /// Play's label when it does something other than start a new activity
  /// ("Continue" for a session already under way); null reads "Play".
  final String? playLabel;

  /// A line under Play's label naming what it opens, e.g. the activity being
  /// continued.
  final String? playDetail;

  /// The tutorial target id Play claims when this card is the one the course
  /// tutorial points at ([TutorialTargetIds.missionPlayButton]); null
  /// everywhere else.
  final String? playTutorialTargetId;
  final VoidCallback onPractice;

  /// The Mission's activity row, under an "Activities" label at the foot of
  /// the card; null draws neither.
  final Widget? activities;

  const MissionCard({
    required this.group,
    required this.index,
    required this.progress,
    required this.breakdown,
    required this.onPlay,
    required this.onPractice,
    this.playLabel,
    this.playDetail,
    this.playTutorialTargetId,
    this.activities,
    super.key,
  });

  static const double _ringSize = 84.0;
  static const double _ringStroke = 9.0;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(24.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pangea = theme.pangea;
    final l10n = L10n.of(context);
    final numbers = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );

    final progress = this.progress;
    final satisfied = progress?.satisfied ?? false;
    final threshold = progress?.threshold ?? 0;
    final breakdown = this.breakdown ?? MissionXpBreakdown.zero;
    final wordCount = group.lemmas.length;

    // The course panel's own surface, so the card reads as part of the page;
    // only its brand-purple edge and the hard lip below it set it apart.
    final cardFill = scheme.surface;

    final palette = MissionRingPalette.of(context);
    final ringTrack = palette.track;
    final chatGold = palette.chat;
    final goalGold = palette.goals;
    final practiceGold = palette.practice;

    final ring = Semantics(
      label: progress == null
          ? null
          : l10n.xpTowardObjective(progress.xp, progress.threshold),
      child: ExcludeSemantics(
        child: MissionXpRing(
          size: _ringSize,
          strokeWidth: _ringStroke,
          trackColor: ringTrack,
          gapColor: cardFill,
          segments: palette.segmentsFor(breakdown, threshold),
          child: progress == null
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      numbers.format(progress.xp),
                      style: theme.textTheme.titleMedium?.copyWith(
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
    );

    final index = this.index;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardFill,
        borderRadius: _radius,
        border: Border.all(color: scheme.primary, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.45),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14.0, 12.0, 14.0, 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10.0,
          children: [
            if (index != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(999.0),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10.0,
                      vertical: 3.0,
                    ),
                    child: Text(
                      l10n.missionNumber(index).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            // The star leads the statement: it is this Mission's star — the
            // one the analytics bar counts — there from the start and filled
            // once the Mission is complete (quests.instructions.md, "Stars
            // and checkmarks").
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8.0,
              children: [
                MissionStar(satisfied: satisfied, size: 28.0),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    // Never larger than the course title above the card
                    // (PanelHeader.titleStyle).
                    child: Text(
                      group.objective.objective,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                ring,
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8.0,
                    children: [
                      if (progress != null)
                        Row(
                          spacing: 6.0,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16.0,
                              // Decorative: the text beside it says it.
                              color: pangea.goldFixedDim,
                            ),
                            Flexible(
                              child: Text(
                                satisfied
                                    ? l10n.missionStarEarned
                                    : l10n.xpToYourStar(
                                        numbers.format(
                                          progress.threshold - progress.xp,
                                        ),
                                      ),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      Wrap(
                        spacing: 10.0,
                        runSpacing: 4.0,
                        children: [
                          _XpSourceLegend(
                            color: chatGold,
                            label: l10n.xpFromChats(
                              numbers.format(breakdown.chat),
                            ),
                          ),
                          _XpSourceLegend(
                            color: goalGold,
                            label: l10n.xpFromGoals(
                              numbers.format(breakdown.goals),
                            ),
                          ),
                          _XpSourceLegend(
                            color: practiceGold,
                            label: l10n.xpFromPractice(
                              numbers.format(breakdown.practice),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            PulsingGlow(
              enabled: onPlay != null && !satisfied,
              color: scheme.primary,
              borderRadius: const BorderRadius.all(Radius.circular(18.0)),
              child: MissionPlayButton(
                onPressed: onPlay,
                label: playLabel,
                detail: playDetail,
                tutorialTargetId: playTutorialTargetId,
              ),
            ),
            BoldTonalButton(
              icon: Symbols.fitness_center,
              label: l10n.practice,
              semanticsLabel: '${l10n.practice}, ${l10n.wordCount(wordCount)}',
              expand: true,
              onPressed: onPractice,
              trailing: wordCount > 0
                  ? _CountChip(l10n.wordCount(wordCount))
                  : null,
            ),
            if (activities != null) ...[
              const SizedBox(height: 4.0),
              Text(
                l10n.activities,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              activities!,
            ],
          ],
        ),
      ),
    );
  }
}

class _XpSourceLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _XpSourceLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4.0,
      children: [
        Container(
          width: 10.0,
          height: 10.0,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.outline, width: 1.0),
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The word count beside Practice.
class _CountChip extends StatelessWidget {
  final String text;

  const _CountChip(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.all(Radius.circular(999.0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 1.0),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSecondaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
