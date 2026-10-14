import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/tutorials/tutorial_target.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';

/// The course page's Mission card (#9420 prototype): which Mission, its
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
  final VoidCallback onPractice;

  /// The course tutorial's "your progress" step lights the ring.
  final String? tutorialTargetId;

  const MissionCard({
    required this.group,
    required this.index,
    required this.progress,
    required this.breakdown,
    required this.onPlay,
    required this.onPractice,
    this.playLabel,
    this.playDetail,
    this.tutorialTargetId,
    super.key,
  });

  static const double _ringSize = 108.0;
  static const double _ringStroke = 12.0;
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
    final wordCount = {
      for (final activity in group.activities)
        for (final word in activity.plan.vocab) word.lemma.toLowerCase(),
    }.length;

    // The course panel's own surface, so the card reads as part of the page;
    // only its brand-purple edge and the hard lip below it set it apart
    // (#9420 prototype, option K).
    final cardFill = scheme.surface;

    final palette = MissionRingPalette.of(context);
    final ringTrack = palette.track;
    final chatGold = palette.chat;
    final goalGold = palette.goals;
    final practiceGold = palette.practice;
    double share(int xp) => threshold <= 0 ? 0 : xp / threshold;

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
          segments: [
            MissionXpRingSegment(
              fraction: share(breakdown.chat),
              color: chatGold,
            ),
            MissionXpRingSegment(
              fraction: share(breakdown.goals),
              color: goalGold,
            ),
            MissionXpRingSegment(
              fraction: share(breakdown.practice),
              color: practiceGold,
            ),
          ],
          child: progress == null
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      numbers.format(progress.xp),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      '/ ${numbers.format(progress.threshold)} XP',
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
        padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12.0,
          children: [
            Row(
              children: [
                if (index != null)
                  DecoratedBox(
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
              ],
            ),
            // The star leads the statement: it is this Mission's star — the
            // one the analytics bar counts — there from the start and filled
            // once the Mission is complete (quests.instructions.md, "Stars
            // and checkmarks").
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8.0,
              children: [
                // Dark outline while the Mission is open; bright gold inside
                // that outline once it's earned, the outline carrying the
                // contrast on the light card.
                Semantics(
                  label: satisfied ? l10n.missionStarEarned : null,
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: 40.0,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (satisfied)
                            Icon(
                              Icons.star_rounded,
                              size: 36.0,
                              color: pangea.goldFixedDim,
                            ),
                          Icon(
                            Icons.star_outline_rounded,
                            size: 40.0,
                            color: scheme.onSurface,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      group.objective.objective,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            TutorialTarget(
              targetId: tutorialTargetId,
              child: Row(
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
                                size: 20.0,
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
                                  style: theme.textTheme.titleSmall?.copyWith(
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
            ),
            _PulsingGlow(
              enabled: onPlay != null && !satisfied,
              color: scheme.primary,
              borderRadius: const BorderRadius.all(Radius.circular(18.0)),
              child: _PlayButton(
                onPressed: onPlay,
                label: playLabel,
                detail: playDetail,
              ),
            ),
            _PracticeWordsButton(onPressed: onPractice, wordCount: wordCount),
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

class _PlayButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? label;
  final String? detail;

  const _PlayButton({required this.onPressed, this.label, this.detail});

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(18.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null;
    final fill = enabled ? scheme.primary : scheme.surfaceContainerHighest;
    final ink = enabled ? scheme.onPrimary : scheme.onSurfaceVariant;
    final label = this.label ?? L10n.of(context).playMission;
    final detail = this.detail;
    return Semantics(
      button: true,
      enabled: enabled,
      label: detail == null ? label : '$label: $detail',

      child: ExcludeSemantics(
        child: PressableButton(
          borderRadius: _radius,
          color: fill,
          buttonHeight: 5.0,
          onPressed: onPressed,
          builder: (context, depressed, shadowColor) => Container(
            constraints: const BoxConstraints(minHeight: 60.0),
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            decoration: BoxDecoration(
              color: depressed ? shadowColor : fill,
              borderRadius: _radius,
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8.0,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 32.0, color: ink),
                    Text(
                      label,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (detail != null)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w600,
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

class _PracticeWordsButton extends StatelessWidget {
  final VoidCallback onPressed;
  final int wordCount;

  const _PracticeWordsButton({
    required this.onPressed,
    required this.wordCount,
  });

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(999.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context);
    final fill = scheme.secondaryContainer;
    final ink = scheme.onSecondaryContainer;
    return Semantics(
      button: true,
      label: '${l10n.practiceWords}, ${l10n.wordCount(wordCount)}',
      child: ExcludeSemantics(
        child: PressableButton(
          borderRadius: _radius,
          color: fill,
          onPressed: onPressed,
          builder: (context, depressed, shadowColor) => Container(
            height: 46.0,
            decoration: BoxDecoration(
              color: depressed ? shadowColor : fill,
              borderRadius: _radius,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8.0,
              children: [
                Icon(Symbols.fitness_center, size: 20.0, color: ink),
                Text(
                  l10n.practiceWords,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (wordCount > 0)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.6),
                      borderRadius: _radius,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 1.0,
                      ),
                      child: Text(
                        l10n.wordCount(wordCount),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

/// A soft glow that breathes out from behind [child] to draw the eye to the
/// one thing to press. Still when [enabled] is false or the platform asks for
/// reduced motion.
class _PulsingGlow extends StatefulWidget {
  final bool enabled;
  final Color color;
  final BorderRadius borderRadius;
  final Widget child;

  const _PulsingGlow({
    required this.enabled,
    required this.color,
    required this.borderRadius,
    required this.child,
  });

  @override
  State<_PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<_PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _PulsingGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.enabled && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final t = Curves.easeOut.transform(_controller.value);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: _controller.isAnimating
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.45 * (1 - t)),
                    spreadRadius: 10.0 * t,
                  ),
                ]
              : null,
        ),
        child: child,
      );
    },
  );
}
