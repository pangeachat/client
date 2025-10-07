class TranslateActivityRequest {
  String activityId;
  String l1;

  TranslateActivityRequest({
    required this.activityId,
    required this.l1,
  });

  Map<String, dynamic> toJson() => {
        "activity_id": activityId,
        "l1": l1,
      };

  factory TranslateActivityRequest.fromJson(Map<String, dynamic> json) {
    return TranslateActivityRequest(
      activityId: json['activity_id'],
      l1: json['l1'],
    );
  }
}
