import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_xp_label.dart';
import 'package:fluffychat/widgets/goal_diamond.dart';
import 'package:fluffychat/widgets/goal_question_mark.dart';
import 'package:fluffychat/widgets/matrix.dart';

class GoalStatusWidget extends StatelessWidget {
  /// A bare diamond's box: the 28 icon plus 4 padding a side.
  static const double diamondBox = 36.0;

  final ActivityRoleGoal goal;
  final bool complete;

  final bool isActive;
  final bool showLabel;

  final TextStyle textStyle;
  final String? starTarget;

  /// What an earned goal pays, drawn as a small gold "+N" under its diamond
  /// (#9559). When set, the line is reserved under every diamond, earned or
  /// not, so earning one never shifts the row. Null draws the diamond alone.
  /// Only on the bare diamond ([showLabel] false).
  final int? goalXp;

  const GoalStatusWidget({
    required this.goal,
    required this.complete,
    this.isActive = false,
    this.showLabel = true,
    this.textStyle = const TextStyle(fontSize: 15),
    this.starTarget,
    this.goalXp,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // A goal is a diamond, never a star: the star marks the Learning
    // Objective this goal pays into (quests.instructions.md).
    // A discussion's question reads as a question mark (#9647).
    Widget icon = GoalMarkScope.of(context) == GoalMarkStyle.question
        ? GoalQuestionMark(earned: complete, size: 28.0)
        : GoalDiamond(earned: complete, size: 28.0);

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

    final goalXp = this.goalXp;
    if (!showLabel && goalXp != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          // Held under every diamond, earned or not, at the label's own
          // height — which follows the text size, so it never clips.
          Visibility(
            visible: complete,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: GoalXpLabel(xp: goalXp),
          ),
        ],
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
