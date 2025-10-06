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
