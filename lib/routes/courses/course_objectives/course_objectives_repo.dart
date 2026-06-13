import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/course_plans/course_activities/course_activity_repo.dart';
import 'package:fluffychat/features/course_plans/course_activities/course_activity_translation_request.dart';
import 'package:fluffychat/features/course_plans/course_topics/course_topic_repo.dart';
import 'package:fluffychat/features/course_plans/course_topics/course_topic_translation_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_plans_repo.dart';
import 'package:fluffychat/features/course_plans/courses/get_localized_courses_request.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// One activity that satisfies a learning objective.
class CourseActivityRef {
  final String activityId;
  final ActivityPlanModel plan;
  const CourseActivityRef({required this.activityId, required this.plan});
}

/// A learning objective in a course, with the activities that satisfy it
/// (world_v2 "Progression"). Courses are sequences of objectives; a learner
/// advances by completing any activity in the objective's bucket.
///
/// Today the bucket is keyed by the activity's per-activity learning-
/// objective text (so it's mostly one activity per objective against
/// staging). Once `learningObjectiveRef` is backfilled and surfaced through
/// the choreo activity payload, several activities collapse onto one shared
/// objective automatically. Objectives have no icons yet — the UI uses a
/// placeholder.
class CourseObjectiveGroup {
  final String objective;
  final List<CourseActivityRef> activities;
  const CourseObjectiveGroup({
    required this.objective,
    required this.activities,
  });
}

/// Builds the learning-objective outline for a single course plan, reusing
/// the cached course-plan repos. Activities are grouped by objective,
/// preserving the plan's topic/activity order.
class CourseObjectivesRepo {
  static Future<List<CourseObjectiveGroup>> objectiveGroups(
    String coursePlanId,
  ) async {
    final l1 = MatrixState.pangeaController.userController.userL1Code ?? 'en';

    // 1. Plan -> ordered topic ids.
    final coursesResp = await CoursePlansRepo.search(
      GetLocalizedCoursesRequest(coursePlanIds: [coursePlanId], l1: l1),
    );
    final plan = coursesResp.coursePlans[coursePlanId];
    if (plan == null || plan.topicIds.isEmpty) return [];

    // 2. Topics (for their ordered activity ids).
    final topicsResp = await CourseTopicRepo.get(
      TranslateTopicRequest(topicIds: plan.topicIds, l1: l1),
      'course_objectives:$coursePlanId',
    );

    // 3. Activity details for every activity in the plan, in plan order.
    final orderedActivityIds = <String>[];
    final seenActivity = <String>{};
    for (final topicId in plan.topicIds) {
      final topic = topicsResp.topics[topicId];
      if (topic == null) continue;
      for (final activityId in topic.activityIds) {
        if (seenActivity.add(activityId)) orderedActivityIds.add(activityId);
      }
    }
    if (orderedActivityIds.isEmpty) return [];
    final activitiesResp = await CourseActivityRepo.get(
      TranslateActivityRequest(activityIds: orderedActivityIds, l1: l1),
      'course_objectives:$coursePlanId',
    );

    // 4. Group by learning objective, preserving first-appearance order.
    final groups = <String, _MutableGroup>{};
    for (final activityId in orderedActivityIds) {
      final activity = activitiesResp.plans[activityId];
      if (activity == null) continue;
      final key = activity.learningObjective.trim();
      final group = groups.putIfAbsent(
        key,
        () => _MutableGroup(objective: activity.learningObjective),
      );
      group.activities.add(
        CourseActivityRef(activityId: activityId, plan: activity),
      );
    }

    return groups.values
        .map(
          (g) => CourseObjectiveGroup(
            objective: g.objective,
            activities: g.activities,
          ),
        )
        .toList();
  }
}

class _MutableGroup {
  final String objective;
  final List<CourseActivityRef> activities = [];
  _MutableGroup({required this.objective});
}
