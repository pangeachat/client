import 'package:fluffychat/features/course_plans/payload_client/models/course_plan/cms_course_plan_topic_location.dart';
import 'package:fluffychat/features/course_plans/payload_client/payload_client.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Read-only access to course topic locations for the world map.
class WorldLocationsRepo {
  static List<CmsCoursePlanTopicLocation>? _cache;
  static DateTime? _lastFetched;
  static const Duration _cacheDuration = Duration(minutes: 10);

  /// All topic locations with usable coordinates. Locations with the
  /// synthetic `[0, 0]` placeholder (coordinates unknown) are excluded.
  static Future<List<CmsCoursePlanTopicLocation>> mappableLocations() async {
    if (_cache != null &&
        _lastFetched != null &&
        DateTime.now().difference(_lastFetched!) < _cacheDuration) {
      return _cache!;
    }

    final payload = PayloadClient(
      baseUrl: Environment.cmsApi,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final List<CmsCoursePlanTopicLocation> locations = [];
    int page = 1;
    bool hasNext = true;
    while (hasNext && page <= 10) {
      final resp = await payload.find(
        CmsCoursePlanTopicLocation.slug,
        CmsCoursePlanTopicLocation.fromJson,
        page: page,
        limit: 100,
      );
      locations.addAll(resp.docs);
      hasNext = resp.hasNextPage;
      page++;
    }

    _cache = locations.where(_hasUsableCoordinates).toList();
    _lastFetched = DateTime.now();
    return _cache!;
  }

  static bool _hasUsableCoordinates(CmsCoursePlanTopicLocation location) {
    final coords = location.coordinates;
    if (coords == null || coords.length != 2) return false;
    return coords[0] != 0 || coords[1] != 0;
  }
}
