import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_event.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsSyncController {
  final Client client;
  final AnalyticsDataService dataService;

  StreamSubscription? _subscription;

  AnalyticsSyncController({
    required this.client,
    required this.dataService,
  });

  void start() {
    _subscription ??= client.onSync.stream.listen(_onSync);
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _onSync(SyncUpdate update) async {
    final analyticsRoom = _getAnalyticsRoom();
    if (analyticsRoom == null) return;

    final events =
        update.rooms?.join?[analyticsRoom.id]?.timeline?.events?.where(
      (e) =>
          e.type == PangeaEventTypes.construct && e.senderId == client.userID,
    );

    if (events == null || events.isEmpty) return;

    final constructEvents = events
        .map(
          (e) => ConstructAnalyticsEvent(
            event: Event.fromMatrixEvent(e, analyticsRoom),
          ),
        )
        .where((e) => e.event.status == EventStatus.synced)
        .toList();

    if (constructEvents.isEmpty) return;
    await dataService.updateServerAnalytics(constructEvents);

    // Server updates do not usually need to update the UI, since usually they are only
    // transfering local data to the server. However, if a user if using multiple devices,
    // we do need to update the UI when new data comes from the server.
    dataService.updateDispatcher.sendConstructAnalyticsUpdate(
      AnalyticsUpdate([]),
    );
  }

  Future<void> waitForSync(String analyticsRoomId) async {
    await client.onSync.stream.firstWhere((update) {
      final roomUpdate = update.rooms?.join?[analyticsRoomId];
      if (roomUpdate == null) return false;

      final hasAnalyticsEvent = roomUpdate.timeline?.events?.any(
            (e) =>
                e.type == PangeaEventTypes.construct &&
                e.senderId == client.userID,
          ) ??
          false;

      return hasAnalyticsEvent;
    });
  }

  Future<void> bulkUpdate() async {
    final analyticsRoom = _getAnalyticsRoom();
    if (analyticsRoom == null) return;

    final lastUpdated = await dataService.getLastUpdatedAnalytics();

    final events = await analyticsRoom.getAnalyticsEvents(
      userId: client.userID!,
      since: lastUpdated,
    );

    if (events == null || events.isEmpty) return;

    await dataService.updateServerAnalytics(events);
  }

  Room? _getAnalyticsRoom() {
    final l2 = MatrixState.pangeaController.userController.userL2;
    if (l2 == null) return null;
    return client.analyticsRoomLocal(l2);
  }
}
