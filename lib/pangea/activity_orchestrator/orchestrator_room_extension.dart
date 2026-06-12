import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension OrchestratorRoomExtension on Room {
  OrchestratorAwardedGoals get orchestratorAwardedGoals {
    final state = getState(PangeaEventTypes.orchestratorAwardedGoals);
    if (state == null) return OrchestratorAwardedGoals(goalIds: []);
    try {
      return OrchestratorAwardedGoals.fromJson(state.content);
    } catch (_) {
      return OrchestratorAwardedGoals(goalIds: []);
    }
  }

  ActivityRoleGoal? get currentGoal {
    final goals = ownRole?.allGoals;
    if (goals == null || goals.isEmpty) return null;

    final awardedGoals = orchestratorAwardedGoals.goalIds;
    return goals.firstWhereOrNull((g) => !awardedGoals.contains(g.id));
  }

  bool isOwnGoalCompleted(String id) {
    final ownRole = this.ownRole;
    if (ownRole == null) return false;
    return orchestratorAwardedGoals.isGoalCompleted(id);
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
    final completedGoals = orchestratorAwardedGoals.goalIds;
    return goals.every((g) => completedGoals.contains(g.id));
  }

  List<ActivityRoleGoal> get ownCompletedGoals {
    final ownRole = this.ownRole;
    if (ownRole == null) return [];

    final ownGoals = ownRole.allGoals;
    final awardedGoals = orchestratorAwardedGoals.goalIds;
    return ownGoals.where((g) => awardedGoals.contains(g.id)).toList();
  }

  bool get haveAllRolesCompletedAllGoals {
    final roles = activityPlan?.roles;
    final assignedRoles = activityRoles?.roles;
    if (roles == null || assignedRoles == null) return false;

    final completedRoles = roles.values.where((r) {
      final assignedRole = assignedRoles[r.id];
      return hasCompletedGoalsByRoleId(r.id) ||
          assignedRole?.userId == BotName.byEnvironment;
    });

    return completedRoles.length >= roles.length;
  }
}
