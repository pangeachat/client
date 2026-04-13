import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_model.dart';
import 'package:fluffychat/pangea/course_plans/localization_error_result.dart';

class TranslateTopicResponse {
  final Map<String, CourseTopicModel> topics;
  final Map<String, LocalizationErrorResult> errors;

  TranslateTopicResponse({required this.topics, this.errors = const {}});

  factory TranslateTopicResponse.fromJson(Map<String, dynamic> json) {
    final topicsEntry = json['topics'] as Map<String, dynamic>;
    final Map<String, CourseTopicModel> topics = {};
    final Map<String, LocalizationErrorResult> errors = {};

    for (final entry in topicsEntry.entries) {
      final value = entry.value as Map<String, dynamic>;
      if (LocalizationErrorResult.isError(value)) {
        errors[entry.key] = LocalizationErrorResult.fromJson(value);
      } else {
        topics[entry.key] = CourseTopicModel.fromJson(value);
      }
    }

    return TranslateTopicResponse(topics: topics, errors: errors);
  }

  Map<String, dynamic> toJson() => {
    "topics": topics.map((key, value) => MapEntry(key, value.toJson())),
  };
}
