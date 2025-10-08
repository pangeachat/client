import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';

class TranslateCoursePlanResponse {
  final Map<String, CoursePlanModel> coursePlans;

  TranslateCoursePlanResponse({required this.coursePlans});

  factory TranslateCoursePlanResponse.fromJson(Map<String, dynamic> json) {
    final plansEntry = json['course_plans'] as Map<String, dynamic>;
    return TranslateCoursePlanResponse(
      coursePlans: plansEntry.map(
        (key, value) => MapEntry(
          key,
          CoursePlanModel.fromJson(value),
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        "course_plans": coursePlans.map(
          (key, value) => MapEntry(
            key,
            value.toJson(),
          ),
        ),
      };
}
