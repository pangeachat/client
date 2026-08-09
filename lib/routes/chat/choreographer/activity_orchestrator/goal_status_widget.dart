import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class GoalStatusWidget extends StatelessWidget {
  final ActivityRoleGoal goal;
  final bool complete;

  final bool isActive;
  final bool showLabel;

  final TextStyle textStyle;
  final String? starTarget;

  const GoalStatusWidget({
    required this.goal,
    required this.complete,
    this.isActive = false,
    this.showLabel = true,
    this.textStyle = const TextStyle(fontSize: 15),
    this.starTarget,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = AppConfig.goldByTheme(context);

    Widget icon = Icon(
      complete ? Icons.star : Icons.star_border,
      color: complete ? gold : null,
      size: 28.0,
    );

    // Every star sits in the same padded box so active and inactive stars line
    // up with each other; only the active one fills its box with a highlight.
    icon = Container(
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? theme.colorScheme.onSurface.withAlpha(26) : null,
      ),
      child: icon,
    );

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

    if (!showLabel) return icon;

    return Row(
      spacing: 12.0,
      children: [
        icon,
        Flexible(child: Text(goal.description, style: textStyle)),
      ],
    );
  }
}
