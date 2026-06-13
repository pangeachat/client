import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class GetLocalizedCoursesRequest {
  final List<String> coursePlanIds;
  final String l1;
  final bool? mock;

  GetLocalizedCoursesRequest({
    required this.coursePlanIds,
    required this.l1,
    this.mock,
  });

  Map<String, dynamic> toJson() => {
    "course_plan_ids": coursePlanIds,
    "l1": l1,
    if (mock != null) ModelKey.mock: mock,
  };

  factory GetLocalizedCoursesRequest.fromJson(Map<String, dynamic> json) {
    return GetLocalizedCoursesRequest(
      coursePlanIds: json['course_plan_ids'] != null
          ? List<String>.from(json['course_plan_ids'])
          : [],
      l1: json['l1'],
    );
  }
}
