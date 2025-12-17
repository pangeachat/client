import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_details_popup/lemma_usage_dots.dart';
import 'package:fluffychat/pangea/analytics_details_popup/lemma_use_example_messages.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/learning_skills_enum.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';

class AnalyticsDetailsViewContent extends StatelessWidget {
  final Widget title;
  final Widget subtitle;
  final Widget headerContent;
  final Widget xpIcon;
  final ConstructUses? construct;

  const AnalyticsDetailsViewContent({
    required this.title,
    required this.subtitle,
    required this.xpIcon,
    required this.headerContent,
    required this.construct,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final level = construct?.lemmaCategory ?? ConstructLevelEnum.seeds;
    final Color textColor = Theme.of(context).brightness != Brightness.light
        ? level.color(context)
        : level.darkColor(context);

    return SingleChildScrollView(
      child: Column(
        children: [
          title,
          const SizedBox(height: 16.0),
          subtitle,
          const SizedBox(height: 16.0),
          headerContent,
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(),
          ),
          if (construct != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                xpIcon,
                const SizedBox(width: 16.0),
                Text(
                  "${construct!.points} XP",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: textColor,
                      ),
                ),
              ],
            ),
          const SizedBox(height: 20),
          if (construct != null)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  LemmaUseExampleMessages(construct: construct!),
                  ...LearningSkillsEnum.values
                      .where((v) => v.isVisible)
                      .map((skill) {
                    return LemmaUsageDots(
                      construct: construct!,
                      category: skill,
                      tooltip: skill.tooltip(context),
                      icon: skill.icon,
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
