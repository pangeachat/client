class ActivityFeedbackRequest {
  final String activityId;
  final String feedbackText;
  final String userId;

  ActivityFeedbackRequest({
    required this.activityId,
    required this.feedbackText,
    required this.userId,
  });

  Map<String, dynamic> toJson() {
    return {
      'activity_id': activityId,
      'feedback_text': feedbackText,
      'user_id': userId,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityFeedbackRequest &&
          runtimeType == other.runtimeType &&
          activityId == other.activityId &&
          feedbackText == other.feedbackText &&
          userId == other.userId;

  @override
  int get hashCode =>
      activityId.hashCode ^ feedbackText.hashCode ^ userId.hashCode;
}
