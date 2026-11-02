import 'package:collection/collection.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';

class ActivityRolesModel {
  final Map<String, ActivityRoleModel> roles;

  const ActivityRolesModel(this.roles);

  ActivityRoleModel? role(String userId) {
    return roles.values.firstWhereOrNull((r) => r.userId == userId);
  }

  /// Writes [role] back to the key its seat is stored under. A roleplay keys
  /// a seat by its role; a discussion by its student, since every student
  /// holds the same role (`participant:<user id>`), so finishing there must
  /// not add a second seat under the role's id.
  void updateRole(ActivityRoleModel role) {
    final key =
        roles.entries
            .firstWhereOrNull(
              (e) => e.value.id == role.id && e.value.userId == role.userId,
            )
            ?.key ??
        role.id;
    roles[key] = role;
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
    return {"roles": roles.map((id, role) => MapEntry(id, role.toJson()))};
  }

  static ActivityRolesModel fromJson(Map<String, dynamic> json) {
    final roles = (json['roles'] as Map<String, dynamic>?)?.map(
      (id, value) => MapEntry(id, ActivityRoleModel.fromJson(value)),
    );

    return ActivityRolesModel(roles ?? {});
  }
}
