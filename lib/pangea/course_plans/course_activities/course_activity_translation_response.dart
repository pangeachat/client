import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';

class TranslateActivityResponse {
  final Map<String, ActivityPlanModel> activities;

  TranslateActivityResponse({required this.activities});

  factory TranslateActivityResponse.fromJson(Map<String, dynamic> json) {
    final activitiesEntry = json['activities'] as Map<String, dynamic>;
    return TranslateActivityResponse(
      activities: activitiesEntry.map(
        (key, value) {
          return MapEntry(
            key,
            ActivityPlanModel.fromJson(value),
          );
        },
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        "activities":
            activities.map((key, value) => MapEntry(key, value.toJson())),
      };
}
