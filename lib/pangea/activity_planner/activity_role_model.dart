class ActivityRoleModel {
  final String userId;
  final String? role;
  DateTime? finishedAt;

  ActivityRoleModel({
    required this.userId,
    this.role,
    this.finishedAt,
  });

  bool get isFinished => finishedAt != null;

  factory ActivityRoleModel.fromJson(Map<String, dynamic> json) {
    return ActivityRoleModel(
      userId: json['userId'],
      role: json['role'],
      finishedAt: json['finishedAt'] != null
          ? DateTime.parse(json['finishedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'role': role,
      'finishedAt': finishedAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ActivityRoleModel &&
        other.userId == userId &&
        other.role == role &&
        other.finishedAt == finishedAt;
  }

  @override
  int get hashCode =>
      userId.hashCode ^ role.hashCode ^ (finishedAt?.hashCode ?? 0);
}
