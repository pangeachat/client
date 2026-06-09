import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_room_extension.dart';
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

  bool isGoalCompleted(String id) {
    final ownRole = this.ownRole;
    if (ownRole == null) return false;
    return orchestratorAwardedGoals.isGoalCompleted(id);
  }

  bool get hasCompletedAllGoals {
    final ownRole = this.ownRole;
    if (ownRole == null) return false;

    final allGoals = ownRole.allGoals;
    return allGoals.every((r) => isGoalCompleted(r.id));
  }

  List<ActivityRoleGoal> get ownCompletedGoals {
    final ownRole = this.ownRole;
    if (ownRole == null) return [];

    final ownGoals = ownRole.allGoals;
    Logs().w("Own Goals: ${ownGoals.map((g) => g.toJson()).toList()}");
    Logs().w("Awarded goals: ${orchestratorAwardedGoals.toJson()}");
    final awardedGoals = orchestratorAwardedGoals.goalIds;
    return ownGoals.where((g) => awardedGoals.contains(g.id)).toList();
  }
}
