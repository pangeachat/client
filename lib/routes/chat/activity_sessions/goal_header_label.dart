import 'package:flutter/widgets.dart';

import 'package:fluffychat/routes/chat/activity_sessions/goal_header_constants.dart';

/// A centered [GoalHeaderConstants.labelStyle] label
class GoalHeaderLabel extends StatelessWidget {
  final String text;

  const GoalHeaderLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: GoalHeaderConstants.labelStyle,
  );
}
