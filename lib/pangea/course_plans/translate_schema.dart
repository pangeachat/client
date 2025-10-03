import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/course_topic_model.dart';

class TranslateCoursePlanRequest {
  String coursePlanId;
  String l1;
  String l2;

  TranslateCoursePlanRequest({
    required this.coursePlanId,
    required this.l1,
    required this.l2,
  });

  Map<String, dynamic> toJson() => {
        "course_plan_id": coursePlanId,
        "l1": l1,
        "l2": l2,
      };

  factory TranslateCoursePlanRequest.fromJson(Map<String, dynamic> json) {
    return TranslateCoursePlanRequest(
      coursePlanId: json['course_plan_id'],
      l1: json['l1'],
      l2: json['l2'],
    );
  }
}

class TranslateCoursePlanResponse {
  final CoursePlanModel? coursePlan;

  TranslateCoursePlanResponse({required this.coursePlan});

  factory TranslateCoursePlanResponse.fromJson(Map<String, dynamic> json) {
    return TranslateCoursePlanResponse(
      coursePlan: json['course_plan'] != null
          ? CoursePlanModel.fromJson(json['course_plan'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        "course_plan": coursePlan?.toJson(),
      };
}

class TranslateTopicRequest {
  String topicId;
  String l1;

  TranslateTopicRequest({
    required this.topicId,
    required this.l1,
  });

  Map<String, dynamic> toJson() => {
        "topic_id": topicId,
        "l1": l1,
      };

  factory TranslateTopicRequest.fromJson(Map<String, dynamic> json) {
    return TranslateTopicRequest(
      topicId: json['topic_id'],
      l1: json['l1'],
    );
  }
}

class TranslateTopicResponse {
  final CourseTopicModel? topic;

  TranslateTopicResponse({required this.topic});

  factory TranslateTopicResponse.fromJson(Map<String, dynamic> json) {
    return TranslateTopicResponse(
      topic: json['topic'] != null
          ? CourseTopicModel.fromJson(json['topic'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        "topic": topic?.toJson(),
      };
}

class TranslateActivityRequest {
  String activityId;
  String l1;
  String l2;

  TranslateActivityRequest({
    required this.activityId,
    required this.l1,
    required this.l2,
  });

  Map<String, dynamic> toJson() => {
        "activity_id": activityId,
        "l1": l1,
        "l2": l2,
      };

  factory TranslateActivityRequest.fromJson(Map<String, dynamic> json) {
    return TranslateActivityRequest(
      activityId: json['activity_id'],
      l1: json['l1'],
      l2: json['l2'],
    );
  }
}

class TranslateActivityResponse {
  final ActivityPlanModel? plan;

  TranslateActivityResponse({required this.plan});

  factory TranslateActivityResponse.fromJson(Map<String, dynamic> json) {
    return TranslateActivityResponse(
      plan: json['plan'] != null
          ? ActivityPlanModel.fromJson(json['plan'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        "plan": plan?.toJson(),
      };
}
