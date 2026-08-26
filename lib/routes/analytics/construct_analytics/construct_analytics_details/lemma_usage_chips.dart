import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';

/// How many uses of one skill row fell in each score bucket.
class UsageChipCounts {
  int positive = 0;
  int negative = 0;
  int neutral = 0;

  bool get isEmpty => positive == 0 && negative == 0 && neutral == 0;
}

/// One row of a construct details page: a skill icon and a "×N" chip per
/// score bucket, plus the heard count on rows that carry exposure.
class LemmaUsageChips extends StatelessWidget {
  final ConstructUses construct;
  final LearningSkillsEnum category;

  final String tooltip;
  final IconData icon;

  const LemmaUsageChips({
    required this.construct,
    required this.category,
    required this.tooltip,
    required this.icon,
    super.key,
  });

  /// Bucket lemma uses for the given skill row by score.
  ///
  /// Counted over ALL uses, not [ConstructUses.cappedUses]: the capped prefix
  /// stops once a construct reaches the flower cap, and a counter frozen at
  /// "×34" reads as broken in a way a wall of dots never did.
  ///
  /// Listening exposure is excluded by use type rather than by being worth
  /// nothing. The distinction matters: plenty of 0-XP uses are real evidence
  /// the learner earned. `ignIGC` and `ignIt` are minted on every sent message
  /// for tokens that writing assistance left alone — i.e. the learner typed the
  /// word and nothing was wrong with it — and they are the bulk of the Writing
  /// row's neutral count. Dropping every 0-XP use would take those with it.
  /// Exposure is excluded because it fires often enough that its place is the
  /// separate [exposureCount] chip — see analytics-system.instructions.md
  /// (Construct Displays).
  UsageChipCounts useCounts(LearningSkillsEnum category) {
    final counts = UsageChipCounts();
    for (final OneConstructUse use in construct.uses) {
      if (category != use.useType.skillsEnumType) continue;
      if (use.useType == ConstructUseTypeEnum.hrd) continue;
      switch (use.xp) {
        case > 0:
          counts.positive++;
        case < 0:
          counts.negative++;
        default:
          counts.neutral++;
      }
    }
    return counts;
  }

  /// How many times this lemma has been heard, for rows that carry exposure.
  ///
  /// Summed over ALL uses rather than [ConstructUses.cappedUses], and summed on
  /// `count` rather than counted by row. A capped figure would freeze at
  /// flowering — under-reporting exposure for exactly the words the learner has
  /// heard most — and one exposure row stands for a whole five-minute window of
  /// hearings, so counting rows would report a number far below what happened.
  int exposureCount(LearningSkillsEnum category) {
    var total = 0;
    for (final OneConstructUse use in construct.uses) {
      if (use.useType != ConstructUseTypeEnum.hrd) continue;
      if (category != use.useType.skillsEnumType) continue;
      total += use.count;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final UsageChipCounts counts = useCounts(category);
    final int heard = exposureCount(category);

    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    final Color textColor = (theme.brightness != Brightness.light
        ? construct.lemmaCategory.color(context)
        : construct.lemmaCategory.darkColor(context));

    // Greys and the heard colour flip with the theme so the chips keep
    // contrast against both card grounds.
    final Color neutralColor = theme.brightness == Brightness.light
        ? Colors.grey[600]!
        : Colors.grey[400]!;
    final Color heardColor = theme.brightness == Brightness.light
        ? AppConfig.primaryColorDark
        : AppConfig.primaryColorLight;

    final List<Widget> chips = [
      if (counts.positive > 0)
        _UsageChip(
          count: counts.positive,
          color: AppConfig.success,
          icon: Icons.check,
          label: l10n.usedCorrectly(counts.positive),
        ),
      if (counts.negative > 0)
        _UsageChip(
          count: counts.negative,
          color: Colors.red,
          icon: Icons.close,
          label: l10n.usedIncorrectly(counts.negative),
        ),
      // The hollow dot echoes the grey dots this chip replaced.
      if (counts.neutral > 0)
        _UsageChip(
          count: counts.neutral,
          color: neutralColor,
          icon: Icons.radio_button_unchecked,
          label: l10n.usedWithoutScoring(counts.neutral),
        ),
      // Last, with its own colour and icon rather than the grey of an unscored
      // use: hearing a word is something that happened TO the learner, not
      // something they did and failed to score on, and the row should not read
      // those as the same thing.
      if (heard > 0)
        _UsageChip(
          count: heard,
          color: heardColor,
          icon: Icons.volume_up,
          label: l10n.timesHeard(heard),
        ),
    ];

    return ListTile(
      leading: Tooltip(
        triggerMode: TooltipTriggerMode.tap,
        message: tooltip,
        child: Icon(icon, size: 24, color: textColor.withValues(alpha: 0.7)),
      ),
      title: chips.isEmpty
          ? Text(
              "-",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: textColor.withAlpha(100),
              ),
            )
          : Wrap(
              spacing: 6,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chips,
            ),
    );
  }
}

/// One "×N" pill: an icon naming its bucket, so buckets stay tellable apart
/// without colour, and a grouped count that reads the same at 24 as at 2,400.
class _UsageChip extends StatelessWidget {
  final int count;
  final Color color;
  final IconData icon;
  final String label;

  const _UsageChip({
    required this.count,
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: label,
      // The pill reads "✓ ×4" visually, which is the same fact in the space
      // available; the label above is what a screen reader should say instead
      // of spelling out an icon and a bare number.
      child: ExcludeSemantics(
        child: Container(
          height: 18.0,
          padding: const EdgeInsets.symmetric(horizontal: 6.0),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(9.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12.0, color: color),
              const SizedBox(width: 3.0),
              Text(
                "×${NumberFormat.decimalPattern(L10n.of(context).localeName).format(count)}",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
