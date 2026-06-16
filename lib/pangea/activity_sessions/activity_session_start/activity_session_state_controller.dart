import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';

abstract class ActivitySessionStateController {
  String? get descriptionText;

  bool isRoleSelected(String id);

  bool isRoleShimmering(String id);

  bool canSelectRole(String id);

  void selectRole(String id);

  bool showStarsCard(String id);

  double get roleCardOpacity;

  bool get goalsStartCollapsed;

  bool get showRoleCards;

  bool get showDescriptionSection;

  Set<String> completedGoalIdsForRole(String id);

  List<ActivityRoleGoal>? get selectedRoleGoals;

  Set<String> get selectedRoleCompletedGoalIds;

  static Set<String> scanCompletedGoalIds({
    required String? activityId,
    required ActivityPlanModel? activity,
    required String roleId,
    required List<Room> rooms,
  }) {
    if (activityId == null) return {};
    final role = activity?.roles[roleId];
    if (role == null) return {};
    final roleGoalIds = role.allGoals.map((g) => g.id).toSet();
    final completed = <String>{};
    for (final room in rooms) {
      if (room.activityId != activityId) continue;
      if (room.ownRoleState?.id != roleId) continue;
      completed.addAll(
        room.orchestratorAwardedGoals.goalIds.where(roleGoalIds.contains),
      );
    }
    return completed;
  }
}
