import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan.dart';
import 'package:fluffychat/pangea/payload_client/paginated_response.dart';

class CoursePlanSearchResponse {
  final List<CoursePlanModel> courses;

  CoursePlanSearchResponse({
    required this.courses,
  });

  factory CoursePlanSearchResponse.fromCmsResponse(
    PayloadPaginatedResponse<CmsCoursePlan> response,
  ) {
    final coursePlans = response.docs
        .map(
          (cmsCoursePlan) => cmsCoursePlan.toCoursePlanModel(),
        )
        .toList();

    return CoursePlanSearchResponse(
      courses: coursePlans,
    );
  }
}
