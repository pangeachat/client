class TeacherModeModel {
  final bool enabled;
  final int? activitiesToUnlockTopic;

  /// Teacher override for the stars a learner must earn in an objective before
  /// the next one unlocks (v3 progression gate; see client quests.instructions.md).
  /// Null falls back to the default threshold. Supersedes the v1
  /// [activitiesToUnlockTopic] count, which gated on completed activities.
  final int? starsToUnlockObjective;

  const TeacherModeModel({
    required this.enabled,
    this.activitiesToUnlockTopic,
    this.starsToUnlockObjective,
  });

  TeacherModeModel copyWith({
    bool? enabled,
    int? activitiesToUnlockTopic,
    int? starsToUnlockObjective,
  }) {
    return TeacherModeModel(
      enabled: enabled ?? this.enabled,
      activitiesToUnlockTopic:
          activitiesToUnlockTopic ?? this.activitiesToUnlockTopic,
      starsToUnlockObjective:
          starsToUnlockObjective ?? this.starsToUnlockObjective,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'activities_to_unlock_topic': activitiesToUnlockTopic,
    'stars_to_unlock_objective': starsToUnlockObjective,
  };

  factory TeacherModeModel.fromJson(Map<String, dynamic> json) {
    return TeacherModeModel(
      enabled: json['enabled'] ?? false,
      activitiesToUnlockTopic: json['activities_to_unlock_topic'],
      starsToUnlockObjective: json['stars_to_unlock_objective'],
    );
  }
}
