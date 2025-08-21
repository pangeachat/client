class CourseUserState {
  final String userID;
  final Map<String, List<String>> _completedActivities;

  CourseUserState({
    required this.userID,
    required Map<String, List<String>> completedActivities,
  }) : _completedActivities = completedActivities;

  void completeActivity(
    String activityID,
    String topicID,
  ) {
    _completedActivities[topicID] ??= [];
    if (!_completedActivities[topicID]!.contains(activityID)) {
      _completedActivities[topicID]!.add(activityID);
    }
  }

  List<String> completedActivities(String topicID) {
    return _completedActivities[topicID] ?? [];
  }

  factory CourseUserState.fromJson(Map<String, dynamic> json) {
    return CourseUserState(
      userID: json['user_id'],
      completedActivities: Map<String, List<String>>.from(
        json['comp_act_by_topic'] ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userID,
      'comp_act_by_topic': _completedActivities,
    };
  }
}
