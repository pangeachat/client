import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension OrchestratorRoomExtension on Room {
  OrchestratorAwardedGoals get orchestratorAwardedGoals {
    final state = getState(PangeaEventTypes.orchestratorAwardedGoals);
    if (state == null) return const OrchestratorAwardedGoals();
    try {
      return OrchestratorAwardedGoals.fromJson(state.content);
    } catch (_) {
      return const OrchestratorAwardedGoals();
    }
  }

  ActivityRoleGoal? get currentGoal {
    final ownRole = this.ownRole;
    final goals = ownRole?.allGoals;
    if (ownRole == null || goals == null || goals.isEmpty) return null;

    final awarded = orchestratorAwardedGoals;
    return goals.firstWhereOrNull(
      (g) => !awarded.isGoalCompletedForRole(ownRole.id, g.id),
    );
  }

  bool isOwnGoalCompleted(String id) {
    final ownRole = this.ownRole;
    if (ownRole == null) return false;
    return orchestratorAwardedGoals.isGoalCompletedForRole(ownRole.id, id);
  }

  bool get hasCompletedOwnGoals {
    final ownRole = this.ownRole;
    if (ownRole == null) return false;
    return hasCompletedGoalsByRoleId(ownRole.id);
  }

  bool hasCompletedGoalsByRoleId(String roleId) {
    final role = activityPlan?.roles[roleId];
    if (role == null) return false;
    final goals = role.allGoals;
    final awarded = orchestratorAwardedGoals;
    return goals.every((g) => awarded.isGoalCompletedForRole(roleId, g.id));
  }

  List<ActivityRoleGoal> get ownCompletedGoals {
    final ownRole = this.ownRole;
    if (ownRole == null) return [];

    final ownGoals = ownRole.allGoals;
    final awarded = orchestratorAwardedGoals;
    return ownGoals
        .where((g) => awarded.isGoalCompletedForRole(ownRole.id, g.id))
        .toList();
  }

  // Every occupant earns their own role's goals — the bot included — so
  // there is no bot exemption here anymore.
  bool get haveAllRolesCompletedAllGoals {
    final roles = activityPlan?.roles;
    final assignedRoles = activityRoles?.roles;
    if (roles == null || assignedRoles == null) return false;

    return roles.values.every((r) => hasCompletedGoalsByRoleId(r.id));
  }
}
