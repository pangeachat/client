import 'package:flutter/widgets.dart';

import 'package:fluffychat/routes/chat/activity_sessions/goal_header_constants.dart';

/// A centered [GoalHeaderConstants.labelStyle] label
class GoalHeaderLabel extends StatelessWidget {
  final String text;

  final int? maxLines;

  const GoalHeaderLabel(this.text, {this.maxLines, super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: GoalHeaderConstants.labelStyle,
    maxLines: maxLines,
    overflow: maxLines != null ? TextOverflow.ellipsis : null,
  );
}
