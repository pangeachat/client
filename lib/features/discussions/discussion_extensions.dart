import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_mode.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';

extension DiscussionPlanExtension on ActivityPlanModel {
  /// The discussion's questions in order, as goals: the goals of its one
  /// shared participant role.
  List<ActivityRoleGoal> get discussionGoals =>
      roles[ActivityMode.discussionRoleId]?.allGoals ??
      const <ActivityRoleGoal>[];

  /// The discussion's questions in order.
  List<String> get discussionQuestions => [
    for (final goal in discussionGoals) goal.description,
  ];
}

extension DiscussionRoomExtension on Room {
  /// The discussion this room is a chat for: a room the server made for a
  /// discussion ([RoomActivityModeExtension.isDiscussionRoom]). Null for
  /// every other room. Known without the plan.
  String? get discussionActivityId =>
      activityMode == ActivityMode.discussion ? activityId : null;
}
