import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_misc/analytics_constants.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension SavedAnalyticsExtension on Room {
  List<String> get activityRoomIds {
    final state = getState(PangeaEventTypes.activityRoomIds);
    if (state?.content[AnalyticsConstants.roomIds] is List) {
      return List<String>.from(
        state!.content[AnalyticsConstants.roomIds] as List,
      );
    }
    return [];
  }

  List<Room> get archivedActivities {
    return activityRoomIds
        .map((id) => client.getRoomById(id))
        .whereType<Room>()
        .where(
          (room) =>
              room.membership != Membership.leave &&
              room.membership != Membership.ban,
        )
        .toList();
  }

  int get archivedActivitiesCount => activityRoomIds.length;

  Future<void> addActivityRoomId(String roomId) async {
    final List<String> ids = List.from(activityRoomIds);
    if (ids.contains(roomId)) return;

    final prevLength = ids.length;
    ids.add(roomId);

    final syncFuture = client.waitForRoomInSync(id, join: true);
    await client.setRoomStateWithKey(id, PangeaEventTypes.activityRoomIds, "", {
      AnalyticsConstants.roomIds: ids,
    });
    final newLength = activityRoomIds.length;
    if (newLength == prevLength) {
      await syncFuture;
    }
  }
}
