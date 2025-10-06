import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan_activity.dart';
import 'package:fluffychat/pangea/payload_client/paginated_response.dart';

class CourseActivitiesImageUrlsRequest {
  final List<CourseActivityMediaIds> activityMediaIds;

  CourseActivitiesImageUrlsRequest({required this.activityMediaIds});

  factory CourseActivitiesImageUrlsRequest.fromCmsResponse(
    PayloadPaginatedResponse<CmsCoursePlanActivity> response,
  ) {
    final activityMediaIds = response.docs
        .map(
          (a) => CourseActivityMediaIds(
            activityId: a.id,
            mediaIds: a.coursePlanActivityMedia?.docs ?? [],
          ),
        )
        .where((a) => a.mediaIds.isNotEmpty)
        .toList();

    return CourseActivitiesImageUrlsRequest(activityMediaIds: activityMediaIds);
  }

  /// A map from media ID to activity ID for all media IDs in the request.
  Map<String, String> get mediaIdsToActivityIds => Map.fromEntries(
        activityMediaIds.where((a) => a.mediaIds.isNotEmpty).map(
              (a) => MapEntry(a.mediaIds.first, a.activityId),
            ),
      );
}

class CourseActivityMediaIds {
  final String activityId;
  final List<String> mediaIds;

  CourseActivityMediaIds({
    required this.activityId,
    required this.mediaIds,
  });
}
