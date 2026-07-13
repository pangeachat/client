import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The overall course progress bar for the course-card HEADER (above the tabs,
/// #7597): the quest's earned-over-threshold stars and a bar. Lives in the
/// header so it shows on every tab and in the collapsed mobile peek — where the
/// objective list (and its old in-list header) isn't even mounted, since the
/// card opens on the chat tab on narrow. Self-resolves the shared progression
/// ([resolveJoinedProgression]); renders a muted empty bar until it lands so the
/// header height (and the peek) stays stable.
class CourseProgressBar extends StatelessWidget {
  final QuestObjectivesLoader objectivesProvider;
  const CourseProgressBar({required this.objectivesProvider, super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: objectivesProvider.progression,
    builder: (context, progression, _) =>
        ProgressBarRow(summary: objectivesProvider.questStars),
  );
}

/// The overall course progress bar: a rounded gold fill over a gray track with
/// a star sitting INSIDE the bar at the goal (right) end — no number. Learners
/// read progress from the fill and tap/hover the bar for the exact
/// earned/threshold (#7597, the Figma course-plan frame). A null [summary]
/// renders the muted empty state (pre-resolve), keeping the header height
/// stable.
class ProgressBarRow extends StatelessWidget {
  final QuestStarSummary? summary;

  static const double _barHeight = 20.0;

  const ProgressBarRow({required this.summary, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = this.summary;
    final gold = AppConfig.goldByTheme(context);
    final fraction = (summary?.fraction ?? 0.0).clamp(0.0, 1.0);
    final label = summary == null
        ? null
        : L10n.of(context).starsEarnedOfTotal(summary.earned, summary.total);

    final bar = SizedBox(
      height: _barHeight,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Gray track.
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(_barHeight / 2),
            ),
            child: const SizedBox.expand(),
          ),
          // Gold fill — the learner's progress toward the goal. The
          // SizedBox.expand child is load-bearing: a childless DecoratedBox in
          // a loose Stack sizes to constraints.smallest (zero height) and
          // paints nothing (#7603).
          FractionallySizedBox(
            widthFactor: fraction,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: gold,
                borderRadius: BorderRadius.circular(_barHeight / 2),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          // The goal star, inside the bar at the right end. A surface-coloured
          // outline star sits behind it so it reads on both the gold fill (full
          // progress) and the gray track.
          Positioned(
            right: 5.0,
            child: SizedBox(
              width: _barHeight - 4,
              height: _barHeight - 4,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.star,
                    size: _barHeight - 3,
                    color: theme.colorScheme.surface,
                  ),
                  Icon(Icons.star, size: _barHeight - 6, color: gold),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final result = Semantics(label: label, value: label, child: bar);

    // Tap (mobile) and hover (desktop) both surface the exact count.
    return label == null
        ? result
        : Tooltip(
            message: label,
            triggerMode: TooltipTriggerMode.tap,
            child: result,
          );
  }
}
