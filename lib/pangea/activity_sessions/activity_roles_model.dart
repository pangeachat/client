import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';

class ActivityRolesModel {
  final Map<String, ActivityRoleModel> roles;
  final bool started;

  const ActivityRolesModel(this.roles, {this.started = false});

  ActivityRoleModel? role(String userId) {
    return roles.values.firstWhereOrNull((r) => r.userId == userId);
  }

  void updateRole(ActivityRoleModel role) {
    roles[role.id] = role;
  }

  void finishAll() {
    for (final id in roles.keys) {
      if (roles[id]!.isFinished) continue;
      roles[id]!.finishedAt = DateTime.now();
    }
  }

  static ActivityRolesModel get empty {
    final roles = <String, ActivityRoleModel>{};
    return ActivityRolesModel(roles);
  }

  Map<String, dynamic> toJson() {
    return {
      "roles": roles.map((id, role) => MapEntry(id, role.toJson())),
      "started": started,
    };
  }

  static ActivityRolesModel fromJson(Map<String, dynamic> json) {
    final roles = (json['roles'] as Map<String, dynamic>)
        .map((id, value) => MapEntry(id, ActivityRoleModel.fromJson(value)));

    return ActivityRolesModel(
      roles,
      started: json['started'] ?? false,
    );
  }
}
