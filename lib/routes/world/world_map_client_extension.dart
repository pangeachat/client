import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';

extension WorldMapClientExtension on Client {
  Room? bestJoinableActivityInstance(String activityId) {
    Room? best;
    for (final r in rooms) {
      if (r.activityId != activityId) continue;
      if (!(r.numRemainingRoles > 0 && r.ownRoleState == null)) continue;
      final ms = r.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      final bestMs =
          best?.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      if (best == null || ms > bestMs) best = r;
    }
    return best;
  }
}
