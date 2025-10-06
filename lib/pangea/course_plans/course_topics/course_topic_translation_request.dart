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
