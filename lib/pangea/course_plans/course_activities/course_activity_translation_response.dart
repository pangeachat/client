import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/localization_error_result.dart';

class TranslateActivityResponse {
  final Map<String, ActivityPlanModel> plans;
  final Map<String, LocalizationErrorResult> errors;

  TranslateActivityResponse({
    required this.plans,
    this.errors = const {},
  });

  factory TranslateActivityResponse.fromJson(Map<String, dynamic> json) {
    final plansEntry = json['plans'] as Map<String, dynamic>;
    final Map<String, ActivityPlanModel> plans = {};
    final Map<String, LocalizationErrorResult> errors = {};

    for (final entry in plansEntry.entries) {
      final value = entry.value as Map<String, dynamic>;
      if (LocalizationErrorResult.isError(value)) {
        errors[entry.key] = LocalizationErrorResult.fromJson(value);
      } else {
        plans[entry.key] = ActivityPlanModel.fromJson(value);
      }
    }

    return TranslateActivityResponse(
      plans: plans,
      errors: errors,
    );
  }

  Map<String, dynamic> toJson() => {
    "plans": plans.map((key, value) => MapEntry(key, value.toJson())),
  };
}
