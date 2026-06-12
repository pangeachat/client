import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/course_plans/course_activities/course_activity_repo.dart';
import 'package:fluffychat/features/course_plans/course_activities/course_activity_translation_request.dart';
import 'package:fluffychat/features/course_plans/course_topics/course_topic_repo.dart';
import 'package:fluffychat/features/course_plans/course_topics/course_topic_translation_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_plans_repo.dart';
import 'package:fluffychat/features/course_plans/courses/get_localized_courses_request.dart';
import 'package:fluffychat/features/course_plans/payload_client/payload_client.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/routes/world/world_locations_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

const String _worldBatchId = 'world_map';

/// One activity placed on the world map at its topic's location.
class WorldActivityPin {
  final String activityId;
  final String title;
  final String locationName;
  final LatLng point;

  /// Course plan this activity's topic belongs to; used to resolve the
  /// course space an activity session should launch under.
  final String coursePlanId;

  const WorldActivityPin({
    required this.activityId,
    required this.title,
    required this.locationName,
    required this.point,
    required this.coursePlanId,
  });
}

/// Builds (activity -> coordinates) pins for the world map.
///
/// Activities carry no geo data themselves; each pin inherits the
/// coordinates of its topic's first mappable location, fanned out in a
/// small ring so co-located activities stay individually tappable.
/// All loads go through the existing caching repos.
class WorldActivitiesRepo {
  static List<WorldActivityPin>? _cache;
  static DateTime? _lastFetched;
  static const Duration _cacheDuration = Duration(minutes: 10);

  static Future<List<WorldActivityPin>> activityPins() async {
    if (_cache != null &&
        _lastFetched != null &&
        DateTime.now().difference(_lastFetched!) < _cacheDuration) {
      return _cache!;
    }

    final l1 = MatrixState.pangeaController.userController.userL1Code ?? 'en';

    // 1. All course plan ids (public CMS read).
    final payload = PayloadClient(
      baseUrl: Environment.cmsApi,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );
    final planIdsResp = await payload.find(
      'course-plans',
      (json) => json['id'] as String,
      limit: 100,
      select: {'id': true},
    );

    // 2. Localized course plans -> topic ids.
    final coursesResp = await CoursePlansRepo.search(
      GetLocalizedCoursesRequest(coursePlanIds: planIdsResp.docs, l1: l1),
    );
    final planIdByTopicId = <String, String>{};
    for (final entry in coursesResp.coursePlans.entries) {
      for (final topicId in entry.value.topicIds) {
        planIdByTopicId[topicId] = entry.key;
      }
    }
    final topicIds = planIdByTopicId.keys.toList();
    if (topicIds.isEmpty) return _setCache([]);

    // 3. Topics -> activity ids + location ids.
    final topicsResp = await CourseTopicRepo.get(
      TranslateTopicRequest(topicIds: topicIds, l1: l1),
      _worldBatchId,
    );

    // 4. Coordinates per location id (raw CMS read keeps coordinates).
    final locations = await WorldLocationsRepo.mappableLocations();
    final coordsById = {
      for (final location in locations) location.id: location,
    };

    // 5. Activity details for topics that can be placed on the map.
    final mappableTopics = topicsResp.topics.values.where(
      (topic) => topic.locationIds.any(coordsById.containsKey),
    );
    final activityIds = mappableTopics
        .expand((topic) => topic.activityIds)
        .toSet()
        .toList();
    if (activityIds.isEmpty) return _setCache([]);
    final activitiesResp = await CourseActivityRepo.get(
      TranslateActivityRequest(activityIds: activityIds, l1: l1),
      _worldBatchId,
    );

    // 6. Pins, fanned out around each topic's location.
    const distance = Distance();
    final pins = <WorldActivityPin>[];
    for (final topic in mappableTopics) {
      final coursePlanId = planIdByTopicId[topic.uuid];
      if (coursePlanId == null) continue;
      final location = topic.locationIds
          .where(coordsById.containsKey)
          .map((id) => coordsById[id]!)
          .first;
      final center = LatLng(location.coordinates![1], location.coordinates![0]);
      final placeable = topic.activityIds
          .where(activitiesResp.plans.containsKey)
          .toList();
      for (var i = 0; i < placeable.length; i++) {
        final plan = activitiesResp.plans[placeable[i]]!;
        // Ring of ~25km around the location; single activities sit on it
        // too so the location pin itself stays visible underneath.
        final point = distance.offset(
          center,
          25000,
          (360 / placeable.length) * i,
        );
        pins.add(
          WorldActivityPin(
            activityId: placeable[i],
            title: plan.title,
            locationName: location.name,
            point: point,
            coursePlanId: coursePlanId,
          ),
        );
      }
    }
    return _setCache(pins);
  }

  static List<WorldActivityPin> _setCache(List<WorldActivityPin> pins) {
    _cache = pins;
    _lastFetched = DateTime.now();
    return pins;
  }
}
