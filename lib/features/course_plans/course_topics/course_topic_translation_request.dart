import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class TranslateTopicRequest {
  List<String> topicIds;
  String l1;
  bool? mock;

  TranslateTopicRequest({required this.topicIds, required this.l1, this.mock});

  Map<String, dynamic> toJson() => {
    "topic_ids": topicIds,
    "l1": l1,
    if (mock != null) ModelKey.mock: mock,
  };

  factory TranslateTopicRequest.fromJson(Map<String, dynamic> json) {
    return TranslateTopicRequest(
      topicIds: json['topic_ids'] != null
          ? List<String>.from(json['topic_ids'])
          : [],
      l1: json['l1'],
    );
  }
}
