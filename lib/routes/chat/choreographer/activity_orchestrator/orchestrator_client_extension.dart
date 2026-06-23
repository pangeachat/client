import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';

extension OrchestratorClientExtension on Client {
  Set<String> scanCompletedGoalIds({
    required String? activityId,
    required ActivityPlanModel? activity,
    required String roleId,
  }) {
    if (activityId == null) return {};
    final role = activity?.roles[roleId];
    if (role == null) return {};
    final completed = <String>{};
    for (final room in rooms) {
      if (room.activityId != activityId) continue;
      if (room.ownRoleState?.id != roleId) continue;
      final awarded = room.orchestratorAwardedGoals;
      for (final g in role.allGoals) {
        if (awarded.isGoalCompletedForRole(
          roleId,
          g.id,
          goalSlug: g.goalSlug,
        )) {
          completed.add(g.id);
        }
      }
    }
    return completed;
  }
}
