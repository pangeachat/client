import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_misc/learning_skills_enum.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';

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

  /// Find lemma uses for the given exercise type, to create dot list
  List<Color> sortedUses(LearningSkillsEnum category) {
    final List<Color> useList = [];
    for (final OneConstructUse use in construct.cappedUses) {
      // If the use type matches the given category, save to list
      // Usage with positive XP is saved as true, else false
      if (category == use.useType.skillsEnumType) {
        useList.add(
          switch (use.xp) {
            > 0 => AppConfig.success,
            < 0 => Colors.red,
            _ => Colors.grey[400]!,
          },
        );
      }
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
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
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
        child: Icon(
          icon,
          size: 24,
          color: textColor.withValues(alpha: 0.7),
        ),
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
          : Wrap(
              spacing: 3,
              runSpacing: 5,
              children: dots,
            ),
    );
  }
}
