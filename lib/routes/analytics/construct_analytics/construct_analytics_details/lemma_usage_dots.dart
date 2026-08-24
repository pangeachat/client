import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
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
  /// One mark per SCORED use only. Zero-XP uses are not marks: listening
  /// exposure alone fires often enough to outnumber everything else here and
  /// turn the row into a wall of identical dots. It is shown as a count
  /// instead — see analytics-system.instructions.md (Construct Displays).
  List<Color> sortedUses(LearningSkillsEnum category) {
    final List<Color> useList = [];
    for (final OneConstructUse use in construct.cappedUses) {
      if (category != use.useType.skillsEnumType) continue;
      if (use.xp == 0) continue;
      useList.add(use.xp > 0 ? AppConfig.success : Colors.red);
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
