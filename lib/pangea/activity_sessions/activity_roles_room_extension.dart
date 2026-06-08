import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

class RoleException implements Exception {
  final String message;
  RoleException(this.message);

  @override
  String toString() => "RoleException: $message";
}

extension ActivityRolesRoomExtension on Room {
  ActivityRolesModel? get activityRoles {
    final content = getState(PangeaEventTypes.activityRole)?.content;
    if (content == null) return null;

    try {
      return ActivityRolesModel.fromJson(content);
    } catch (e, s) {
      if (!kDebugMode && !Environment.isStagingEnvironment) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {"roomID": id, "stateEvent": content},
        );
      }
      return null;
    }
  }

  ActivityRoleModel? get ownRoleState => activityRoles?.role(client.userID!);

  ActivityRole? get ownRole {
    final role = ownRoleState;
    if (role == null || activityPlan == null) return null;

    return activityPlan!.roles[role.id];
  }

  int get numRemainingRoles {
    final availableRoles = activityPlan?.roles;
    return max(0, (availableRoles?.length ?? 0) - (assignedRoles?.length ?? 0));
  }

  bool get isActivityStarted =>
      isActivityFinished ||
      (activityPlan?.roles.length ?? 0) - (assignedRoles?.length ?? 0) <= 0;

  bool get isActivityFinished {
    final roles = activityRoles?.roles.values.where(
      (r) => r.userId != BotName.byEnvironment,
    );

    if (roles == null || roles.isEmpty) return false;
    if (!roles.any((r) => r.isFinished)) return false;

    return roles.every((r) {
      if (r.isFinished) return true;

      // if the user is in the chat (not null && membership is join),
      // then the activity is not finished for them
      final user = getParticipants().firstWhereOrNull((u) => u.id == r.userId);
      return user == null || user.membership != Membership.join;
    });
  }

  bool get hasPickedRole => ownRoleState != null;

  bool get hasCompletedRole => ownRoleState?.isFinished ?? false;

  bool get hasArchivedActivity => ownRoleState?.isArchived ?? false;

  bool get isActiveInActivity => hasPickedRole && !hasCompletedRole;

  Map<String, ActivityRoleModel>? get assignedRoles {
    final roles = activityRoles?.roles;
    if (roles == null) return null;

    final participants = getParticipants();
    return Map.fromEntries(
      roles.entries.where(
        (r) => participants.any(
          (p) => p.id == r.value.userId && p.membership == Membership.join,
        ),
      ),
    );
  }

  Future<void> joinActivity(ActivityRole role) async {
    final assigned = assignedRoles?.values ?? [];
    if (assigned.any((r) => r.userId != client.userID && r.role == role.name)) {
      throw RoleException("Role already taken");
    }

    if (assigned.any((r) => r.userId == client.userID)) {
      throw RoleException("User already has a role");
    }

    final currentRoles = activityRoles ?? ActivityRolesModel.empty;
    final activityRole = ActivityRoleModel(
      id: role.id,
      userId: client.userID!,
      role: role.name,
    );

    currentRoles.updateRole(activityRole);
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activityRole,
      "",
      currentRoles.toJson(),
    );
  }

  Future<void> continueActivity() async {
    final currentRoles = activityRoles ?? ActivityRolesModel.empty;
    final role = ownRoleState;
    if (role == null || !role.isFinished) return;

    role.finishedAt = null; // Reset finished state
    currentRoles.updateRole(role);
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activityRole,
      "",
      currentRoles.toJson(),
    );
  }

  Future<void> finishActivity() async {
    final currentRoles = activityRoles ?? ActivityRolesModel.empty;
    final role = ownRoleState;
    if (role == null || role.isFinished) return;
    role.finishedAt = DateTime.now();
    currentRoles.updateRole(role);

    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activityRole,
      "",
      currentRoles.toJson(),
    );
  }

  Future<void> finishActivityForAll() async {
    final currentRoles = activityRoles ?? ActivityRolesModel.empty;
    currentRoles.finishAll();
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activityRole,
      "",
      currentRoles.toJson(),
    );
  }

  Future<void> archiveActivity() async {
    final currentRoles = activityRoles ?? ActivityRolesModel.empty;
    final role = ownRoleState;
    if (role == null || !role.isFinished || role.isArchived) return;

    role.archivedAt = DateTime.now();
    currentRoles.updateRole(role);
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.activityRole,
      "",
      currentRoles.toJson(),
    );
  }
}
