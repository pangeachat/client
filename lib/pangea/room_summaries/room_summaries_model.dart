import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_model.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/room_summaries/activity_sessions_status_model.dart';
import 'package:fluffychat/pangea/room_summaries/room_summary_extension.dart';

class RoomSummariesModel {
  final Map<String, RoomSummaryResponse> _roomSummaries;
  RoomSummariesModel(this._roomSummaries);

  RoomSummaryResponse? getRoomSummary(String roomId) => _roomSummaries[roomId];
}

class ActivitySessionSummariesModel extends RoomSummariesModel {
  final String activityId;
  ActivitySessionSummariesModel(
    super._roomSummaries, {
    required this.activityId,
  });

  Map<String, RoomSummaryResponse> get _activityInstances =>
      Map<String, RoomSummaryResponse>.fromEntries(
        _roomSummaries.entries.where(
          (e) => e.value.isActivityInstance(activityId),
        ),
      );

  Set<String> get openSessions => _activityInstances.entries
      .where((e) => e.value.isActivityOpenToJoin)
      .map((e) => e.key)
      .toSet();

  ActivitySessionsStatusModel get activitySessionStatuses =>
      ActivitySessionsStatusModel(_activityInstances);
}

class CourseInfoSummariesModel extends RoomSummariesModel {
  final int? activitiesToCompleteOverride;
  CourseInfoSummariesModel(
    super._roomSummaries, {
    this.activitiesToCompleteOverride,
  });

  Set<String> _completedActivities(String userID) => _roomSummaries.values
      .where((e) => e.isCompleteByUserId(userID))
      .map((e) => e.activityPlan?.activityId)
      .whereType<String>()
      .toSet();

  bool hasCompletedActivity(String userID, String activityID) =>
      _completedActivities(userID).contains(activityID);

  bool _hasCompletedTopic(String userID, CourseTopicModel topic) {
    final topicActivityIds = topic.activityIds.toSet();
    final numCompleted = _completedActivities(
      userID,
    ).intersection(topicActivityIds).length;

    final override = activitiesToCompleteOverride;
    return override != null
        ? numCompleted >= override
        : numCompleted >= topic.activitiesToComplete;
  }

  String? currentTopicIdByUser(String userID, CoursePlanModel course) {
    return course.topicIds.firstWhereOrNull((id) {
          final topic = course.loadedTopics[id];
          if (topic == null) return false;
          return !_hasCompletedTopic(userID, topic);
        }) ??
        course.topicIds.lastOrNull;
  }

  Map<String, List<User>> currentTopicIdsToUsers(
    List<User> users,
    CoursePlanModel course,
  ) {
    final Map<String, List<User>> topicUserMap = {};
    for (final user in users) {
      if (user.id == BotName.byEnvironment) continue;
      final topicId = currentTopicIdByUser(user.id, course);
      if (topicId != null) {
        topicUserMap.putIfAbsent(topicId, () => []).add(user);
      }
    }
    return topicUserMap;
  }
}
