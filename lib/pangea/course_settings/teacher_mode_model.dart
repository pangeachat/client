class TeacherModeModel {
  final bool enabled;
  final int? activitiesToUnlockTopic;

  const TeacherModeModel({required this.enabled, this.activitiesToUnlockTopic});

  TeacherModeModel copyWith({bool? enabled, int? activitiesToUnlockTopic}) {
    return TeacherModeModel(
      enabled: enabled ?? this.enabled,
      activitiesToUnlockTopic:
          activitiesToUnlockTopic ?? this.activitiesToUnlockTopic,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'activities_to_unlock_topic': activitiesToUnlockTopic,
  };

  factory TeacherModeModel.fromJson(Map<String, dynamic> json) {
    return TeacherModeModel(
      enabled: json['enabled'] ?? false,
      activitiesToUnlockTopic: json['activities_to_unlock_topic'],
    );
  }
}
