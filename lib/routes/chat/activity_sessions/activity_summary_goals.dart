import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/routes/chat/activity_sessions/goal_header_session_xp.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';

/// The goals of the participant whose summary card is up, shown in place of
/// the goal header once the summary lands (#8289). On the viewer's own card
/// the session XP the header showed tops the list (#9696); another player's
/// card shows none.
class ActivitySummaryGoals extends StatelessWidget {
  final Room room;

  /// The plan role of the participant whose card is up.
  final ActivityRole role;
  final String participantId;

  const ActivitySummaryGoals({
    required this.room,
    required this.role,
    required this.participantId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final awarded = room.orchestratorAwardedGoals;
    return Column(
      spacing: 8.0,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (participantId == room.client.userID)
          GoalHeaderSessionXp(room: room),
        for (final goal in role.allGoals)
          GoalStatusWidget(
            goal: goal,
            complete: awarded.isGoalCompletedForRole(
              role.id,
              goal.id,
              goalSlug: goal.goalSlug,
            ),
          ),
      ],
    );
  }
}
