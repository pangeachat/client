import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

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

  Future<void> _setActivityRoomIds(List<String> activityRoomIds) =>
      client.setRoomStateWithKey(id, PangeaEventTypes.activityRoomIds, "", {
        AnalyticsConstants.roomIds: activityRoomIds,
      });

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

  Future<void> addActivityRoomIds(Set<String> roomIds) async {
    final activityRoomIds = List.from(this.activityRoomIds);
    final currentIds = {...activityRoomIds};
    final newIds = roomIds.difference(currentIds);
    if (newIds.isEmpty) return;

    final syncFuture = client.waitForRoomInSync(id, join: true);
    await _setActivityRoomIds([...activityRoomIds, ...newIds]);
    await syncFuture;
  }
}
