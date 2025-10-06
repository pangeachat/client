import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';

class TranslateActivityResponse {
  final ActivityPlanModel plan;

  TranslateActivityResponse({required this.plan});

  factory TranslateActivityResponse.fromJson(Map<String, dynamic> json) {
    return TranslateActivityResponse(
      plan: ActivityPlanModel.fromJson(json['plan']),
    );
  }

  Map<String, dynamic> toJson() => {
        "plan": plan.toJson(),
      };
}
