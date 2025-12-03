import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';

class ExtendedSpaceRoomsChunk {
  final SpaceRoomsChunk chunk;
  final List<ActivityRoleModel> assignedRoles;

  ExtendedSpaceRoomsChunk({
    required this.chunk,
    required this.assignedRoles,
  });
}
