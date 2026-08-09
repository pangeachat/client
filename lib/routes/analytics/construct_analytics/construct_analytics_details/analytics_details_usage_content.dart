import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/lemma_usage_dots.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/lemma_use_example_messages.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsDetailsUsageContent extends StatelessWidget {
  final ConstructUses construct;

  const AnalyticsDetailsUsageContent({required this.construct, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: LemmaUseExampleMessages(
            construct: construct,
            client: Matrix.of(context).client,
          ),
        ),
        ...LearningSkillsEnum.values.where((v) => v.isVisible).map((skill) {
          return LemmaUsageDots(
            construct: construct,
            category: skill,
            tooltip: skill.tooltip(context),
            icon: skill.icon,
          );
        }),
      ],
    );
  }
}
