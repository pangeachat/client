import 'package:flutter/widgets.dart';

import 'package:fluffychat/routes/chat/activity_sessions/goal_header_constants.dart';
import 'package:fluffychat/widgets/expandable_text.dart';

/// A centered [GoalHeaderConstants.labelStyle] label. With [maxLines], text
/// past the cap collapses behind an inline "Show more" so a long goal can
/// still be read in full (#9318); text that fits renders plainly.
class GoalHeaderLabel extends StatelessWidget {
  final String text;

  final int? maxLines;

  const GoalHeaderLabel(this.text, {this.maxLines, super.key});

  @override
  Widget build(BuildContext context) {
    final maxLines = this.maxLines;
    return maxLines == null
        ? Text(
            text,
            textAlign: TextAlign.center,
            style: GoalHeaderConstants.labelStyle,
          )
        : ExpandableText(
            text,
            style: GoalHeaderConstants.labelStyle,
            maxLines: maxLines,
            textAlign: TextAlign.center,
          );
  }
}
