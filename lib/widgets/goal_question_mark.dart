import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';

/// How goal marks draw below this point: activity goals are diamonds
/// ([GoalDiamond]); a discussion's questions are question marks (#9647), so
/// the two never read as the same thing.
enum GoalMarkStyle { diamond, question }

/// Sets the [GoalMarkStyle] for the goal widgets under it. The goal header
/// is shared by activities and discussions; a discussion wraps it in this
/// rather than threading a flag through every row.
class GoalMarkScope extends InheritedWidget {
  final GoalMarkStyle style;

  const GoalMarkScope({required this.style, required super.child, super.key});

  static GoalMarkStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GoalMarkScope>()?.style ??
      GoalMarkStyle.diamond;

  @override
  bool updateShouldNotify(GoalMarkScope old) => old.style != style;
}

/// One discussion question's mark (#9647): a question mark in a circle,
/// filled with the bright gold once the question is answered, an outline
/// while it is open. The goal diamond's colours, so earning one reads the
/// same.
class GoalQuestionMark extends StatelessWidget {
  final bool earned;
  final double size;

  const GoalQuestionMark({required this.earned, required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final edge = earned
        ? theme.pangea.goldGraphic
        : theme.colorScheme.onSurfaceVariant;
    final stroke = (size * 0.1).clamp(1.0, 3.0);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: earned ? theme.pangea.goldFixedDim : null,
        border: Border.all(color: edge, width: stroke),
      ),
      child: Text(
        '?',
        style: TextStyle(
          fontSize: size * 0.62,
          height: 1.0,
          fontWeight: FontWeight.w900,
          color: earned ? theme.pangea.onGoldFixed : edge,
        ),
      ),
    );
  }
}
