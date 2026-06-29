import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class GoalStatusWidget extends StatelessWidget {
  final ActivityRoleGoal goal;
  final bool complete;
  final String? starTarget;
  final int? maxLines;

  const GoalStatusWidget({
    required this.goal,
    required this.complete,
    this.starTarget,
    this.maxLines,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget icon = complete
        ? Icon(
            Icons.star,
            color: theme.brightness == Brightness.light
                ? AppConfig.gold
                : AppConfig.goldLight,
            size: 30.0,
          )
        : Icon(Icons.star_border, size: 30.0);

    final starTarget = this.starTarget;
    if (starTarget != null) {
      icon = CompositedTransformTarget(
        link: MatrixState.pAnyState.layerLinkAndKey(starTarget).link,
        child: Container(
          key: MatrixState.pAnyState.layerLinkAndKey(starTarget).key,
          child: icon,
        ),
      );
    }

    return Row(
      spacing: 12.0,
      children: [
        icon,
        Flexible(
          child: Text(
            goal.description,
            maxLines: maxLines,
            overflow: maxLines != null ? TextOverflow.ellipsis : null,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
