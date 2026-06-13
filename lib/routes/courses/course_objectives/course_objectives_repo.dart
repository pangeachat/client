import 'package:collection/collection.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/course_plans/course_activities/course_activity_repo.dart';
import 'package:fluffychat/features/course_plans/course_activities/course_activity_translation_request.dart';
import 'package:fluffychat/features/course_plans/course_topics/course_topic_repo.dart';
import 'package:fluffychat/features/course_plans/course_topics/course_topic_translation_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_plans_repo.dart';
import 'package:fluffychat/features/course_plans/courses/get_localized_courses_request.dart';
import 'package:fluffychat/features/course_plans/payload_client/models/course_plan/cms_course_plan_topic_location.dart';
import 'package:fluffychat/routes/world/world_locations_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// One learning objective in a course's left-column outline (world_v2).
///
/// In this pass the objective is labelled by the activity's per-activity
/// learning-objective text. Once `learningObjectiveRef` is backfilled on
/// staging/prod and surfaced through the choreo activity payload, several
/// activities collapse onto one shared bucket label here.
class CourseObjectiveItem {
  final String activityId;
  final String title;
  final String objective;
  final LatLng? point;

  const CourseObjectiveItem({
    required this.activityId,
    required this.title,
    required this.objective,
    this.point,
  });
}

/// The objectives of a course grouped by the location their activities sit
/// at. The city/location name is derived from the activity map data, not a
/// nested course-structure field (world_v2 "Progression").
class CourseLocationGroup {
  final String locationName;
  final LatLng? point;
  final List<CourseObjectiveItem> objectives;

  const CourseLocationGroup({
    required this.locationName,
    required this.point,
    required this.objectives,
  });
}

/// Builds the location-grouped objective outline for a single course plan.
/// Reuses the cached course-plan repos (same chain as the world map).
class CourseObjectivesRepo {
  static Future<List<CourseLocationGroup>> forCoursePlan(
    String coursePlanId,
  ) async {
    final l1 = MatrixState.pangeaController.userController.userL1Code ?? 'en';

    // 1. Plan -> ordered topic ids.
    final coursesResp = await CoursePlansRepo.search(
      GetLocalizedCoursesRequest(coursePlanIds: [coursePlanId], l1: l1),
    );
    final plan = coursesResp.coursePlans[coursePlanId];
    if (plan == null || plan.topicIds.isEmpty) return [];

    // 2. Topics.
    final topicsResp = await CourseTopicRepo.get(
      TranslateTopicRequest(topicIds: plan.topicIds, l1: l1),
      'course_objectives:$coursePlanId',
    );

    // 3. Coordinates + names per location id.
    final locations = await WorldLocationsRepo.mappableLocations();
    final locationById = <String, CmsCoursePlanTopicLocation>{
      for (final l in locations) l.id: l,
    };

    // 4. Activity details for every activity in the plan's topics.
    final activityIds = plan.topicIds
        .map((id) => topicsResp.topics[id])
        .nonNulls
        .expand((topic) => topic.activityIds)
        .toSet()
        .toList();
    if (activityIds.isEmpty) return [];
    final activitiesResp = await CourseActivityRepo.get(
      TranslateActivityRequest(activityIds: activityIds, l1: l1),
      'course_objectives:$coursePlanId',
    );

    // 5. Group objectives by location, preserving plan/topic order.
    final groups = <String, _MutableGroup>{};
    for (final topicId in plan.topicIds) {
      final topic = topicsResp.topics[topicId];
      if (topic == null) continue;

      final location = topic.locationIds
          .map((id) => locationById[id])
          .firstWhereOrNull((l) => l != null);
      final name = location?.name ?? topic.title;
      final coords = location?.coordinates;
      final point = coords != null && coords.length == 2
          ? LatLng(coords[1], coords[0])
          : null;

      final group = groups.putIfAbsent(
        name,
        () => _MutableGroup(name: name, point: point),
      );
      for (final activityId in topic.activityIds) {
        final activity = activitiesResp.plans[activityId];
        if (activity == null) continue;
        group.objectives.add(
          CourseObjectiveItem(
            activityId: activityId,
            title: activity.title,
            objective: activity.learningObjective,
            point: point,
          ),
        );
      }
    }

    return groups.values
        .map(
          (g) => CourseLocationGroup(
            locationName: g.name,
            point: g.point,
            objectives: g.objectives,
          ),
        )
        .where((g) => g.objectives.isNotEmpty)
        .toList();
  }
}

class _MutableGroup {
  final String name;
  final LatLng? point;
  final List<CourseObjectiveItem> objectives = [];
  _MutableGroup({required this.name, required this.point});
}
