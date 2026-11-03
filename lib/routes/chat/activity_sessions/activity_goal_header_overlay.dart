import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/widgets/embed_pointer_shield.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goal_header_card.dart';

/// A live chat's goal header, pinned over the top of the timeline: the
/// roleplay goal menu and a discussion's questions. Open, it dims the
/// timeline, and a tap on the dim closes it ([onDismiss]).
class ActivityGoalHeaderOverlay extends StatelessWidget {
  final bool showDropdown;
  final bool isComplete;
  final Widget collapsed;
  final Widget expanded;
  final VoidCallback onDismiss;

  const ActivityGoalHeaderOverlay({
    super.key,
    required this.showDropdown,
    required this.isComplete,
    required this.collapsed,
    required this.expanded,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    bottom: showDropdown ? 0 : null,
    child: Stack(
      children: [
        if (showDropdown) ...[
          // Same reason as the card's own shield (#9063): the dim covers the
          // timeline, and a tap on it over a live video embed would otherwise
          // reach the video instead of closing the dropdown.
          const Positioned.fill(child: EmbedPointerShield()),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: ColoredBox(color: Colors.black.withAlpha(100)),
            ),
          ),
        ],
        ActivityGoalHeaderCard(
          showDropdown: showDropdown,
          isComplete: isComplete,
          collapsed: collapsed,
          expanded: expanded,
        ),
      ],
    ),
  );
}
