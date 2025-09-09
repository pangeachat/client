class CourseUserState {
  final String userID;
  final List<String> _completedActivities;
  final List<String> _joinActivities;

  CourseUserState({
    required this.userID,
    required List<String> completedActivities,
    required List<String> joinActivities,
  })  : _completedActivities = completedActivities,
        _joinActivities = joinActivities;

  void joinActivity(
    String activityID,
  ) {
    if (!_joinActivities.contains(activityID)) {
      _joinActivities.add(activityID);
    }
  }

  void completeActivity(
    String activityID,
  ) {
    if (!_completedActivities.contains(activityID)) {
      _completedActivities.add(activityID);
    }
  }

  List<String> get completedActivities => _completedActivities;

  bool hasCompletedActivity(
    String activityID,
  ) {
    return _completedActivities.contains(activityID);
  }

  factory CourseUserState.fromJson(Map<String, dynamic> json) {
    final activityEntry =
        List<String>.from((json['comp_act_by_topic'] as List<dynamic>?) ?? []);
    final joinEntry =
        List<String>.from((json['join_act_by_topic'] as List<dynamic>?) ?? []);

    return CourseUserState(
      userID: json['user_id'],
      completedActivities: activityEntry,
      joinActivities: joinEntry,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userID,
      'comp_act_by_topic': _completedActivities,
      'join_act_by_topic': _joinActivities,
    };
  }
}
