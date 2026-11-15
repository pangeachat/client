import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

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

  /// Whether the orchestrator has awarded the learner [goalId] in this room.
  /// Read under [ActivityRolesRoomExtension.ownAwardKey], so a discussion's
  /// per-seat awards count like a roleplay's per-role ones.
  bool _isOwnGoalAwarded(
    OrchestratorAwardedGoals awarded,
    String goalId, {
    String? goalSlug,
  }) {
    final key = ownAwardKey;
    if (key == null) return false;
    return awarded.isGoalCompletedForRole(key, goalId, goalSlug: goalSlug);
  }

  ActivityRoleGoal? get currentGoal {
    final goals = ownRole?.allGoals;
    if (goals == null || goals.isEmpty) return null;

    final awarded = orchestratorAwardedGoals;
    return goals.firstWhereOrNull(
      (g) => !_isOwnGoalAwarded(awarded, g.id, goalSlug: g.goalSlug),
    );
  }

  bool isOwnGoalCompleted(String id, {String? goalSlug}) {
    if (ownRole == null) return false;
    return _isOwnGoalAwarded(orchestratorAwardedGoals, id, goalSlug: goalSlug);
  }

  bool get hasCompletedOwnGoals {
    final goals = ownRole?.allGoals;
    if (goals == null) return false;
    final awarded = orchestratorAwardedGoals;
    return goals.every(
      (g) => _isOwnGoalAwarded(awarded, g.id, goalSlug: g.goalSlug),
    );
  }

  bool hasCompletedGoalsByRoleId(String roleId) {
    final role = activityPlan?.roles[roleId];
    if (role == null) return false;
    final goals = role.allGoals;
    final awarded = orchestratorAwardedGoals;
    return goals.every(
      (g) => awarded.isGoalCompletedForRole(roleId, g.id, goalSlug: g.goalSlug),
    );
  }

  List<ActivityRoleGoal> get ownCompletedGoals {
    final ownGoals = ownRole?.allGoals;
    if (ownGoals == null) return [];

    final awarded = orchestratorAwardedGoals;
    return ownGoals
        .where((g) => _isOwnGoalAwarded(awarded, g.id, goalSlug: g.goalSlug))
        .toList();
  }

  bool get haveAllRolesCompletedAllGoals {
    final roles = activityPlan?.roles;
    final assignedRoles = activityRoles?.roles;
    if (roles == null || assignedRoles == null) return false;

    return roles.values.every((r) {
      final assigned = assignedRoles[r.id];
      if (assigned?.userId == BotName.byEnvironment) return true;
      return hasCompletedGoalsByRoleId(r.id);
    });
  }
}
