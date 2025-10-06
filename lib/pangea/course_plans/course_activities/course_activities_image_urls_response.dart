import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan_activity_media.dart';
import 'package:fluffychat/pangea/payload_client/paginated_response.dart';

class CourseActivitiesImageUrlsResponse {
  final Map<String, String> imageUrls;

  CourseActivitiesImageUrlsResponse({required this.imageUrls});

  factory CourseActivitiesImageUrlsResponse.fromCmsResponse(
    PayloadPaginatedResponse<CmsCoursePlanActivityMedia> response,
    Map<String, String> mediaIdToActivityId,
  ) {
    final imageUrls = Map.fromEntries(
      response.docs.map((media) {
        final activityId = mediaIdToActivityId[media.id];
        if (activityId != null && media.url != null) {
          return MapEntry(activityId, '${Environment.cmsApi}${media.url!}');
        }
        return null;
      }).whereType<MapEntry<String, String>>(),
    );

    return CourseActivitiesImageUrlsResponse(imageUrls: imageUrls);
  }
}
