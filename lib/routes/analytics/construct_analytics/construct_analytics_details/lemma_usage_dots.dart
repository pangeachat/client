import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
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
  /// else, not because it scores nothing; it is shown as a count instead — see
  /// analytics-system.instructions.md (Construct Displays).
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

  @override
  Widget build(BuildContext context) {
    final List<Widget> dots = [];
    for (final Color color in sortedUses(category)) {
      dots.add(
        Container(
          width: 15.0,
          height: 15.0,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );
    }

    final Color textColor = (Theme.of(context).brightness != Brightness.light
        ? construct.lemmaCategory.color(context)
        : construct.lemmaCategory.darkColor(context));

    return ListTile(
      leading: Tooltip(
        triggerMode: TooltipTriggerMode.tap,
        message: tooltip,
        child: Icon(icon, size: 24, color: textColor.withValues(alpha: 0.7)),
      ),
      title: dots.isEmpty
          ? Text(
              "-",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: textColor.withAlpha(100),
              ),
            )
          : Wrap(spacing: 3, runSpacing: 5, children: dots),
    );
  }
}
