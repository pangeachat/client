import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';

class TranslateCoursePlanResponse {
  final CoursePlanModel coursePlan;

  TranslateCoursePlanResponse({required this.coursePlan});

  factory TranslateCoursePlanResponse.fromJson(Map<String, dynamic> json) {
    return TranslateCoursePlanResponse(
      coursePlan: CoursePlanModel.fromJson(json['course_plan']),
    );
  }

  Map<String, dynamic> toJson() => {
        "course_plan": coursePlan.toJson(),
      };
}
