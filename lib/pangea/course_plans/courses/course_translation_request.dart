class TranslateCoursePlanRequest {
  final String coursePlanId;
  final String l1;

  TranslateCoursePlanRequest({
    required this.coursePlanId,
    required this.l1,
  });

  Map<String, dynamic> toJson() => {
        "course_plan_id": coursePlanId,
        "l1": l1,
      };

  factory TranslateCoursePlanRequest.fromJson(Map<String, dynamic> json) {
    return TranslateCoursePlanRequest(
      coursePlanId: json['course_plan_id'],
      l1: json['l1'],
    );
  }
}
