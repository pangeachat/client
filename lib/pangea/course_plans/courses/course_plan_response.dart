import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan.dart';

class CoursePlanResponse {
  final CoursePlanModel course;

  CoursePlanResponse({
    required this.course,
  });

  factory CoursePlanResponse.fromCmsResponse(CmsCoursePlan cmsCoursePlan) {
    return CoursePlanResponse(
      course: cmsCoursePlan.toCoursePlanModel(),
    );
  }
}
