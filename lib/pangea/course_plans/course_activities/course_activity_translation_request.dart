import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class TranslateActivityRequest {
  List<String> activityIds;
  String l1;
  bool? mock;

  TranslateActivityRequest({
    required this.activityIds,
    required this.l1,
    this.mock,
  });

  Map<String, dynamic> toJson() => {
    "activity_ids": activityIds,
    "l1": l1,
    if (mock != null) ModelKey.mock: mock,
  };

  factory TranslateActivityRequest.fromJson(Map<String, dynamic> json) {
    return TranslateActivityRequest(
      activityIds: json['activity_ids'] != null
          ? List<String>.from(json['activity_ids'])
          : [],
      l1: json['l1'],
    );
  }
}
