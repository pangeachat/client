import 'package:flutter/material.dart';

import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The current Mission's position in the plan and its can-do statement, the
/// first thing under the course page's Learning Objective header (#9437).
/// The meter and the Mission's activities follow it.
class CurrentObjectiveStatement extends StatelessWidget {
  final QuestObjectiveGroup group;

  /// 1-based position among the rendered Missions, or null when unknown.
  final int? index;
  final int count;

  const CurrentObjectiveStatement({
    required this.group,
    required this.index,
    required this.count,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = this.index;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2.0,
      children: [
        if (index != null)
          Text(
            L10n.of(context).missionNofM(index, count),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        Text(
          group.objective.objective,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
