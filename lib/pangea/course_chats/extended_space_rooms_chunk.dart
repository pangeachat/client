import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';

class ExtendedSpaceRoomsChunk {
  final SpaceRoomsChunk$2 chunk;
  final List<ActivityRoleModel> assignedRoles;
  final ActivityPlanModel activity;

  ExtendedSpaceRoomsChunk({
    required this.chunk,
    required this.assignedRoles,
    required this.activity,
  });
}
