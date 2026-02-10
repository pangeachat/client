import 'package:fluffychat/pangea/common/constants/model_keys.dart';

/// Generic feedback schema matching the backend's LLMFeedbackSchema.
/// Used for providing user corrections to LLM-generated content.
class LLMFeedbackModel<T> {
  /// User's feedback text describing the issue
  final String feedback;

  /// Original response that user is providing feedback on
  final T content;

  /// Function to serialize the content to JSON
  final Map<String, dynamic> Function(T) contentToJson;

  const LLMFeedbackModel({
    required this.feedback,
    required this.content,
    required this.contentToJson,
  });

  Map<String, dynamic> toJson() => {
    ModelKey.feedback: feedback,
    ModelKey.content: contentToJson(content),
  };
}
