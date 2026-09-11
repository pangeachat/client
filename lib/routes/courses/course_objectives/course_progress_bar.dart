import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/tutorials/tutorial_target.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The overall course progress bar for the course page: the quest's
/// earned-over-threshold stars and a bar. It rides the page's intro block
/// (under the Catch up card, #8357) and stands alone in the collapsed mobile
/// peek — where the sections aren't even mounted — so a learner always sees
/// course progress without scrolling. Reads the shared progression the
/// [QuestObjectivesLoader] resolves and keeps current; renders a muted empty
/// bar until it lands so the layout (and the peek) stays stable.
class CourseProgressBar extends StatelessWidget {
  final QuestObjectivesLoader objectivesProvider;

  /// Registers this bar as a tutorial spotlight target. Only the course page's
  /// instance passes one; the bar renders in three places ([TutorialTarget]).
  final String? tutorialTargetId;

  const CourseProgressBar({
    required this.objectivesProvider,
    this.tutorialTargetId,
    super.key,
  });

  @override
  Widget build(BuildContext context) => TutorialTarget(
    targetId: tutorialTargetId,
    child: ValueListenableBuilder(
      valueListenable: objectivesProvider.progression,
      builder: (context, progression, _) =>
          ProgressBarRow(summary: objectivesProvider.questStars),
    ),
  );
}

/// The overall course progress bar: a rounded bright-gold fill, edged in the mark gold, over a gold-container track with
/// a star sitting INSIDE the bar at the goal (right) end — no number. Learners
/// read progress from the fill and tap/hover the bar for the exact
/// earned/threshold (#7597, the Figma course-plan frame). A null [summary]
/// renders the muted empty state (pre-resolve), keeping the header height
/// stable.
class ProgressBarRow extends StatelessWidget {
  final QuestStarSummary? summary;

  /// The track's height. Published so the course context bar can state its
  /// own height from its parts ([CourseContextBar.height]).
  static const double height = 20.0;
  static const double _barHeight = height;

  const ProgressBarRow({required this.summary, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = this.summary;
    final fraction = (summary?.fraction ?? 0.0).clamp(0.0, 1.0);
    final label = summary == null
        ? null
        : L10n.of(context).starsEarnedOfTotal(summary.earned, summary.total);

    final bar = SizedBox(
      height: _barHeight,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // The track: the gold container, so the mark gold reads on it.
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.pangea.goldContainer,
              borderRadius: BorderRadius.circular(_barHeight / 2),
            ),
            child: const SizedBox.expand(),
          ),
          if (fraction != 0)
            LayoutBuilder(
              builder: (context, constraints) {
                // Too little progress can make gold bar look strange
                final double maxWidth = constraints.maxWidth;
                final containerWidth = math.max(
                  _barHeight,
                  maxWidth * fraction,
                );
                // Gold fill — the learner's progress toward the goal. The bright
                // gold cannot clear 3:1 on any light track, so a hairline in the
                // mark gold carries the fill's edge instead. The SizedBox.expand
                // child is load-bearing: a childless DecoratedBox in a loose
                // Stack sizes to constraints.smallest (zero height) and paints
                // nothing (#7603).
                return SizedBox(
                  width: containerWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.pangea.goldFixedDim,
                      border: Border.all(color: theme.pangea.goldGraphic),
                      borderRadius: BorderRadius.circular(_barHeight / 2),
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          // The goal star, inside the bar at the right end, in the mark gold so
          // it clears 3:1 on the track; at full progress it sits on the fill as
          // the silhouette the surface-coloured outline star behind it draws.
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
                  Icon(
                    Icons.star,
                    size: _barHeight - 6,
                    color: theme.pangea.goldGraphic,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // Tap (mobile) and hover (desktop) both surface the exact count.
    return Semantics(
      container: true,
      child: label == null
          ? bar
          : Tooltip(
              message: label,
              triggerMode: TooltipTriggerMode.tap,
              child: bar,
            ),
    );
  }
}
