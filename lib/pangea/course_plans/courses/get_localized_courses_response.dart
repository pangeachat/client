import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/localization_error_result.dart';

class GetLocalizedCoursesResponse {
  final Map<String, CoursePlanModel> coursePlans;
  final Map<String, LocalizationErrorResult> errors;
  final bool hasNextPage;

  GetLocalizedCoursesResponse({
    required this.coursePlans,
    this.errors = const {},
    this.hasNextPage = false,
  });

  factory GetLocalizedCoursesResponse.fromJson(Map<String, dynamic> json) {
    final plansEntry = json['course_plans'] as Map<String, dynamic>;
    final Map<String, CoursePlanModel> coursePlans = {};
    final Map<String, LocalizationErrorResult> errors = {};

    for (final entry in plansEntry.entries) {
      final value = entry.value as Map<String, dynamic>;
      if (LocalizationErrorResult.isError(value)) {
        errors[entry.key] = LocalizationErrorResult.fromJson(value);
      } else {
        coursePlans[entry.key] = CoursePlanModel.fromJson(value);
      }
    }

    return GetLocalizedCoursesResponse(
      coursePlans: coursePlans,
      errors: errors,
    );
  }

  Map<String, dynamic> toJson() => {
    "course_plans": coursePlans.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };
}
