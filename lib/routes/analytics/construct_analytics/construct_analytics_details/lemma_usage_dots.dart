import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';

class LemmaUsageDots extends StatelessWidget {
  final ConstructUses construct;
  final LearningSkillsEnum category;

  final String tooltip;
  final IconData icon;

  const LemmaUsageDots({
    required this.construct,
    required this.category,
    required this.tooltip,
    required this.icon,
    super.key,
  });

  /// Find lemma uses for the given exercise type, to create dot list.
  ///
  /// One mark per use, EXCEPT listening exposure, which is excluded by use type
  /// rather than by being worth nothing.
  ///
  /// The distinction matters: plenty of existing 0-XP uses are real evidence
  /// the learner earned. `ignIGC` and `ignIt` are minted on every sent message
  /// for tokens that writing assistance left alone — i.e. the learner typed the
  /// word and nothing was wrong with it — and they are the most common thing in
  /// the Writing row. Dropping every 0-XP use would take those with it.
  /// Exposure is excluded because it fires often enough to bury everything
  /// else, not because it scores nothing; it is shown as [exposureCount]
  /// instead — see analytics-system.instructions.md (Construct Displays).
  List<Color> sortedUses(LearningSkillsEnum category) {
    final List<Color> useList = [];
    for (final OneConstructUse use in construct.cappedUses) {
      if (category != use.useType.skillsEnumType) continue;
      if (use.useType == ConstructUseTypeEnum.hrd) continue;
      useList.add(switch (use.xp) {
        > 0 => AppConfig.success,
        < 0 => Colors.red,
        _ => Colors.grey[400]!,
      });
    }
    return useList;
  }

  /// How many times this lemma has been heard, for rows that carry exposure.
  ///
  /// Summed over ALL uses rather than [ConstructUses.cappedUses], and summed on
  /// `count` rather than counted by row. Both differ from the marks above on
  /// purpose:
  ///
  /// - the capped prefix stops once a construct reaches the flower cap, so a
  ///   capped figure would freeze at flowering — under-reporting exposure for
  ///   exactly the words the learner has heard most;
  /// - one exposure row stands for a whole five-minute window of hearings, so
  ///   counting rows would report a number far below what happened.
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
    final List<Color> markColors = sortedUses(category);
    final int heard = exposureCount(category);

    final Color textColor = (Theme.of(context).brightness != Brightness.light
        ? construct.lemmaCategory.color(context)
        : construct.lemmaCategory.darkColor(context));

    final List<Widget> marks = [
      for (final Color color in markColors)
        Container(
          width: 15.0,
          height: 15.0,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      // Last, and one of them however many hearings it stands for. This is the
      // whole point of the count: a row of marks grows with what the learner
      // did, and exposure would otherwise swamp it.
      if (heard > 0) _HeardCount(count: heard),
    ];

    return ListTile(
      leading: Tooltip(
        triggerMode: TooltipTriggerMode.tap,
        message: tooltip,
        child: Icon(icon, size: 24, color: textColor.withValues(alpha: 0.7)),
      ),
      title: marks.isEmpty
          ? Text(
              "-",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: textColor.withAlpha(100),
              ),
            )
          : Wrap(
              spacing: 3,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: marks,
            ),
    );
  }
}

/// How many times the lemma was heard, as one pill.
///
/// Fixed width for any magnitude beyond its digits, which is what lets the
/// listening row stay readable when exposure runs to the thousands.
class _HeardCount extends StatelessWidget {
  final int count;

  const _HeardCount({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Its own colour rather than the grey of an unscored use: hearing a word is
    // something that happened TO the learner, not something they did and failed
    // to score on, and the row should not read those as the same thing.
    final Color color = theme.brightness == Brightness.light
        ? AppConfig.primaryColorDark
        : AppConfig.primaryColorLight;

    return Semantics(
      label: L10n.of(context).timesHeard(count),
      // The pill reads "x24" visually, which is the same fact in the space
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
              Icon(Icons.volume_up, size: 12.0, color: color),
              const SizedBox(width: 3.0),
              Text(
                // Grouped, so a four-figure count reads at a glance rather
                // than needing to be counted out.
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
