class TranslateCoursePlanRequest {
  final List<String> coursePlanIds;
  final String l1;

  TranslateCoursePlanRequest({
    required this.coursePlanIds,
    required this.l1,
  });

  Map<String, dynamic> toJson() => {
        "course_plan_ids": coursePlanIds,
        "l1": l1,
      };

  factory TranslateCoursePlanRequest.fromJson(Map<String, dynamic> json) {
    return TranslateCoursePlanRequest(
      coursePlanIds: json['course_plan_ids'] != null
          ? List<String>.from(json['course_plan_ids'])
          : [],
      l1: json['l1'],
    );
  }
}
