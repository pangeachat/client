import 'dart:math';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';

extension QuestsClientExtension on Client {
  Map<String, int> get userStarsByActivity {
    final stars = <String, int>{};
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null) continue;

      final current = stars[activityId] ?? 0;
      final collected = room.ownCompletedGoals.length;
      stars[activityId] = max(current, collected);
    }
    return stars;
  }
}
