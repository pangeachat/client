import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';

class TranslateActivityResponse {
  final Map<String, ActivityPlanModel> plans;

  TranslateActivityResponse({required this.plans});

  factory TranslateActivityResponse.fromJson(Map<String, dynamic> json) {
    final plansEntry = json['plans'] as Map<String, dynamic>;
    return TranslateActivityResponse(
      plans: plansEntry.map(
        (key, value) {
          final valueWithId = value["original_activity_id"] == null
              ? {...value, "original_activity_id": key}
              : value;

          return MapEntry(
            key,
            ActivityPlanModel.fromJson(valueWithId),
          );
        },
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        "plans": plans.map((key, value) => MapEntry(key, value.toJson())),
      };
}
