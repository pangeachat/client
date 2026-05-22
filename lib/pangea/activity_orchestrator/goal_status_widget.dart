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
    final theme = Theme.of(context);

    final icon = complete
        ? Icon(
            Icons.star,
            color: theme.brightness == Brightness.light
                ? AppConfig.gold
                : AppConfig.goldLight,
            size: 30.0,
          )
        : Icon(Icons.star_border, size: 30.0);

    return Row(
      spacing: 12.0,
      children: [
        icon,
        Flexible(
          child: Text(
            goal.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
