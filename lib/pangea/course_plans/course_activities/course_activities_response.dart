import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/course_activities/course_activities_image_urls_response.dart';
import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan_activity.dart';
import 'package:fluffychat/pangea/payload_client/paginated_response.dart';

class CourseActivitiesResponse {
  final List<ActivityPlanModel> activities;

  CourseActivitiesResponse({required this.activities});

  factory CourseActivitiesResponse.fromCmsResponse(
    PayloadPaginatedResponse<CmsCoursePlanActivity> response,
    CourseActivitiesImageUrlsResponse mediaResponse,
  ) {
    final activities = response.docs
        .map((a) => a.toActivityPlanModel(mediaResponse.imageUrls[a.id]))
        .toList();

    return CourseActivitiesResponse(activities: activities);
  }
}
