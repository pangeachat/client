import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_model.dart';

class TranslateTopicResponse {
  final CourseTopicModel topic;

  TranslateTopicResponse({required this.topic});

  factory TranslateTopicResponse.fromJson(Map<String, dynamic> json) {
    return TranslateTopicResponse(
      topic: CourseTopicModel.fromJson(json['topic']),
    );
  }

  Map<String, dynamic> toJson() => {
        "topic": topic.toJson(),
      };
}
