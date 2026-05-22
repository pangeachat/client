import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';

class GoalStatusWidget extends StatelessWidget {
  final ActivityRoleGoal goal;
  final bool complete;

  const GoalStatusWidget({
    required this.goal,
    required this.complete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final icon = complete
        ? Icon(Icons.star, color: AppConfig.goldLight)
        : Icon(Icons.star_border);

    return Row(
      spacing: 12.0,
      children: [
        icon,
        Text(goal.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
