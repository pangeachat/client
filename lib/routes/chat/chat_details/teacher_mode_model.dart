class TeacherModeModel {
  final bool enabled;
  final int? activitiesToUnlockTopic;

  /// The v3 star threshold that [xpToCompleteObjective] superseded (#9420).
  /// Still parsed so an older client's write survives a round trip, but
  /// nothing reads it: a stored "10 stars" must not be mistaken for "10 XP".
  final int? starsToUnlockObjective;

  /// Teacher override for the XP a learner must earn toward a Mission for it
  /// to count as complete (client quests.instructions.md, "What fills a
  /// Mission"). Null falls back to the default threshold.
  final int? xpToCompleteObjective;

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
    this.xpToCompleteObjective,
    this.pinnedActivitiesByObjective,
  });

  TeacherModeModel copyWith({
    bool? enabled,
    int? activitiesToUnlockTopic,
    int? starsToUnlockObjective,
    int? xpToCompleteObjective,
    Map<String, List<String>>? pinnedActivitiesByObjective,
  }) {
    return TeacherModeModel(
      enabled: enabled ?? this.enabled,
      activitiesToUnlockTopic:
          activitiesToUnlockTopic ?? this.activitiesToUnlockTopic,
      starsToUnlockObjective:
          starsToUnlockObjective ?? this.starsToUnlockObjective,
      xpToCompleteObjective:
          xpToCompleteObjective ?? this.xpToCompleteObjective,
      pinnedActivitiesByObjective:
          pinnedActivitiesByObjective ?? this.pinnedActivitiesByObjective,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'activities_to_unlock_topic': activitiesToUnlockTopic,
    'stars_to_unlock_objective': starsToUnlockObjective,
    if (xpToCompleteObjective != null)
      'xp_to_complete_objective': xpToCompleteObjective,
    if (pinnedActivitiesByObjective != null)
      'pinned_activities_by_objective': pinnedActivitiesByObjective,
  };

  factory TeacherModeModel.fromJson(Map<String, dynamic> json) {
    final rawPins = json['pinned_activities_by_objective'];
    return TeacherModeModel(
      enabled: json['enabled'] ?? false,
      activitiesToUnlockTopic: json['activities_to_unlock_topic'],
      starsToUnlockObjective: json['stars_to_unlock_objective'],
      xpToCompleteObjective: json['xp_to_complete_objective'] is int
          ? json['xp_to_complete_objective']
          : null,
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
