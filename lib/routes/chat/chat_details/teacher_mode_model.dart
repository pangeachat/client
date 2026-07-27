class TeacherModeModel {
  final bool enabled;
  final int? activitiesToUnlockTopic;

  /// Teacher override for the stars a learner must earn in an objective before
  /// the next one unlocks (v3 progression gate; see client quests.instructions.md).
  /// Null falls back to the default threshold. Supersedes the v1
  /// [activitiesToUnlockTopic] count, which gated on completed activities.
  final int? starsToUnlockObjective;

  /// Per-course activity pinning: Mission (LO) id → the activity content ids
  /// (`activity_id`, environment-stable — never CMS row ids) that satisfy the
  /// Mission in this course's context. Null / missing key / empty list mean no
  /// restriction — pinning is opt-in per Mission and fails open, so a pin can
  /// never make a Mission unsatisfiable (org quests doc). Independent of
  /// [enabled], which only toggles the teacher's own viewing mode.
  final Map<String, List<String>>? pinnedActivitiesByObjective;

  const TeacherModeModel({
    required this.enabled,
    this.activitiesToUnlockTopic,
    this.starsToUnlockObjective,
    this.pinnedActivitiesByObjective,
  });

  TeacherModeModel copyWith({
    bool? enabled,
    int? activitiesToUnlockTopic,
    int? starsToUnlockObjective,
    Map<String, List<String>>? pinnedActivitiesByObjective,
  }) {
    return TeacherModeModel(
      enabled: enabled ?? this.enabled,
      activitiesToUnlockTopic:
          activitiesToUnlockTopic ?? this.activitiesToUnlockTopic,
      starsToUnlockObjective:
          starsToUnlockObjective ?? this.starsToUnlockObjective,
      pinnedActivitiesByObjective:
          pinnedActivitiesByObjective ?? this.pinnedActivitiesByObjective,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'activities_to_unlock_topic': activitiesToUnlockTopic,
    'stars_to_unlock_objective': starsToUnlockObjective,
    if (pinnedActivitiesByObjective != null)
      'pinned_activities_by_objective': pinnedActivitiesByObjective,
  };

  factory TeacherModeModel.fromJson(Map<String, dynamic> json) {
    final rawPins = json['pinned_activities_by_objective'];
    return TeacherModeModel(
      enabled: json['enabled'] ?? false,
      activitiesToUnlockTopic: json['activities_to_unlock_topic'],
      starsToUnlockObjective: json['stars_to_unlock_objective'],
      pinnedActivitiesByObjective: rawPins is Map
          ? {
              for (final entry in rawPins.entries)
                if (entry.key is String && entry.value is List)
                  entry.key as String: (entry.value as List)
                      .whereType<String>()
                      .toList(),
            }
          : null,
    );
  }
}
