import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// "I'm teaching this course": a per-admin flag on the course room, stored
/// under the admin's own user id so every member can read it. A teacher sees
/// every Mission unlocked and is left off the leaderboard ranking; an admin
/// who isn't teaching plays as a student (#9333 prototype).
extension CourseTeacherRoomExtension on Room {
  static const String _teachingKey = 'teaching';

  /// Only a current admin can be a teacher, so a demoted admin's leftover
  /// flag stops counting.
  bool isTeaching(String userId) {
    if (getPowerLevelByUserId(userId) < SpaceConstants.powerLevelOfAdmin) {
      return false;
    }
    final content = getState(PangeaEventTypes.courseTeacher, userId)?.content;
    return content?[_teachingKey] == true;
  }

  bool get isOwnTeaching {
    final userId = client.userID;
    return userId != null && isTeaching(userId);
  }

  Future<void> toggleOwnTeaching() async {
    final userId = client.userID;
    if (userId == null) return;
    final syncFuture = client.waitForRoomInSync(id);
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.courseTeacher,
      userId,
      {_teachingKey: !isOwnTeaching},
    );
    await syncFuture;
  }
}
