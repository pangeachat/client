class TranslateCoursePlanRequest {
  final String coursePlanId;
  final String l1;
  final String l2;

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
