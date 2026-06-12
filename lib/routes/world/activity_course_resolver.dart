import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_repo.dart';
import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_translation_request.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plans_repo.dart';
import 'package:fluffychat/pangea/course_plans/courses/get_localized_courses_request.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Resolves which of the user's joined course spaces an activity belongs
/// to. Used to share new activity sessions into matching course spaces
/// and to scope completion lookups for the world-map popup.
class ActivityCourseResolver {
  /// Joined course spaces whose course plan includes [activityId] and
  /// whose target language matches [activityL2] (region-insensitive,
  /// e.g. `es` matches `es-MX`). Null [activityL2] skips the L2 check.
  static Future<List<Room>> matchingCourseSpaces(
    Client client,
    String activityId,
    String? activityL2,
  ) async {
    final spaces = client.rooms
        .where(
          (room) =>
              room.isSpace &&
              room.membership == Membership.join &&
              room.coursePlan != null,
        )
        .toList();
    if (spaces.isEmpty) return [];

    final l1 = MatrixState.pangeaController.userController.userL1Code ?? 'en';
    final planIds = spaces.map((s) => s.coursePlan!.uuid).toSet().toList();
    final plans = await CoursePlansRepo.search(
      GetLocalizedCoursesRequest(coursePlanIds: planIds, l1: l1),
    );

    String short(String code) => code.split('-').first.toLowerCase();
    final planIdByTopicId = <String, String>{};
    for (final entry in plans.coursePlans.entries) {
      if (activityL2 != null &&
          short(entry.value.targetLanguage) != short(activityL2)) {
        continue;
      }
      for (final topicId in entry.value.topicIds) {
        planIdByTopicId[topicId] = entry.key;
      }
    }
    if (planIdByTopicId.isEmpty) return [];

    final topics = await CourseTopicRepo.get(
      TranslateTopicRequest(topicIds: planIdByTopicId.keys.toList(), l1: l1),
      'activity_course_resolver',
    );

    final matchingPlanIds = <String>{};
    for (final topic in topics.topics.values) {
      if (topic.activityIds.contains(activityId)) {
        matchingPlanIds.add(planIdByTopicId[topic.uuid]!);
      }
    }

    return spaces
        .where((s) => matchingPlanIds.contains(s.coursePlan!.uuid))
        .toList();
  }
}
