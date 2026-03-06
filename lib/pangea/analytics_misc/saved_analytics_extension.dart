import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension SavedAnalyticsExtension on Room {
  List<String> get _activityRoomIds {
    final state = getState(PangeaEventTypes.activityRoomIds);
    if (state?.content[ModelKey.roomIds] is List) {
      return List<String>.from(state!.content[ModelKey.roomIds] as List);
    }
    return [];
  }

  List<Room> get archivedActivities {
    return _activityRoomIds
        .map((id) => client.getRoomById(id))
        .whereType<Room>()
        .where(
          (room) =>
              room.membership != Membership.leave &&
              room.membership != Membership.ban,
        )
        .toList();
  }

  int get archivedActivitiesCount => archivedActivities.length;

  Future<void> addActivityRoomId(String roomId) async {
    final List<String> ids = List.from(_activityRoomIds);
    if (ids.contains(roomId)) return;

    final prevLength = ids.length;
    ids.add(roomId);

    final syncFuture = client.waitForRoomInSync(id, join: true);
    await client.setRoomStateWithKey(id, PangeaEventTypes.activityRoomIds, "", {
      ModelKey.roomIds: ids,
    });
    final newLength = _activityRoomIds.length;
    if (newLength == prevLength) {
      await syncFuture;
    }
  }
}
