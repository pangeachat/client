import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/start_practice.dart';

/// What the course page's Learning Objective section shows once every
/// Mission with an activity is complete (#9437): there is no next Mission to
/// name (#8997), so the section says the course is done and offers practice
/// to keep what was learned fresh. The full plan behind "See all" still lists
/// every Mission, each with its check.
class CourseCompleteCard extends StatelessWidget {
  final int objectiveCount;

  const CourseCompleteCard({required this.objectiveCount, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        // The completion green of the circles, not the primary purple: the
        // Practice button is primary and vanished against it.
        color: theme.pangea.successContainer,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8.0,
        children: [
          Row(
            spacing: 8.0,
            children: [
              Icon(Icons.check_circle, size: 32.0, color: theme.pangea.success),
              Expanded(
                child: Text(
                  l10n.courseComplete,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.pangea.onSuccessContainer,
                  ),
                ),
              ),
            ],
          ),
          Text(
            l10n.courseCompleteDesc(objectiveCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.pangea.onSuccessContainer,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: () => startPractice(context, ConstructTypeEnum.vocab),
              icon: const Icon(Symbols.fitness_center, size: 18),
              label: Text(l10n.practice),
            ),
          ),
        ],
      ),
    );
  }
}
