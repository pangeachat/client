import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';

mixin ActivitySessionStateController {
  String? get descriptionText;

  bool isRoleSelected(String id) => false;

  bool isRoleShimmering(String id) => false;

  bool canSelectRole(String id) => false;

  void selectRole(String id) {}

  bool showStarsCard(String id) => false;

  double get roleCardOpacity => 1.0;

  bool get goalsStartCollapsed => false;

  bool get showRoleCards => true;

  bool get showDescriptionSection => true;

  Set<String> completedGoalIdsForRole(String id) => {};

  List<ActivityRoleGoal>? get selectedRoleGoals => null;

  Set<String> get selectedRoleCompletedGoalIds => {};

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
