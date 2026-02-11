import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_event.dart';
import 'package:fluffychat/pangea/analytics_settings/analytics_settings_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/lemmas/user_set_lemma_info.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum _AnalyticsUpdateEvent {
  constructAnalytics,
  activityAnalytics,
  lemmaInfo,
  blockedConstruct;

  String get eventType {
    switch (this) {
      case _AnalyticsUpdateEvent.constructAnalytics:
        return PangeaEventTypes.construct;
      case _AnalyticsUpdateEvent.activityAnalytics:
        return PangeaEventTypes.activityRoomIds;
      case _AnalyticsUpdateEvent.lemmaInfo:
        return PangeaEventTypes.userSetLemmaInfo;
      case _AnalyticsUpdateEvent.blockedConstruct:
        return PangeaEventTypes.analyticsSettings;
    }
  }
}

class AnalyticsSyncController {
  final Client client;
  final AnalyticsDataService dataService;

  StreamSubscription? _subscription;

  AnalyticsSyncController({required this.client, required this.dataService});

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

    final roomUpdates = update.rooms?.join?[analyticsRoom.id]?.timeline?.events;
    if (roomUpdates == null) return;

    for (final type in _AnalyticsUpdateEvent.values) {
      await _dispatchSyncEvents(type, roomUpdates, analyticsRoom);
    }
  }

  Future<void> _dispatchSyncEvents(
    _AnalyticsUpdateEvent type,
    List<MatrixEvent> events,
    Room analyticsRoom,
  ) async {
    final updates = events
        .where((e) => e.type == type.eventType && e.senderId == client.userID)
        .toList();

    switch (type) {
      case _AnalyticsUpdateEvent.constructAnalytics:
        await _onConstructEvents(updates, analyticsRoom);
        break;
      case _AnalyticsUpdateEvent.activityAnalytics:
        _onActivityEvents(updates);
        break;
      case _AnalyticsUpdateEvent.lemmaInfo:
        _onLemmaInfoEvents(updates);
        break;
      case _AnalyticsUpdateEvent.blockedConstruct:
        await _onBlockedConstructEvents(updates);
        break;
    }
  }

  Future<void> _onConstructEvents(
    List<MatrixEvent> events,
    Room analyticsRoom,
  ) async {
    final constructEvents = events
        .map(
          (e) => ConstructAnalyticsEvent(
            event: Event.fromMatrixEvent(e, analyticsRoom),
          ),
        )
        .where((e) => e.event.status == EventStatus.synced)
        .toList();

    if (constructEvents.isEmpty) return;
    await dataService.updateDispatcher.sendServerAnalyticsUpdate(
      constructEvents,
    );
  }

  void _onActivityEvents(List<MatrixEvent> events) {
    for (final event in events) {
      if (event.content[ModelKey.roomIds] is! List) continue;
      final roomIds = List<String>.from(
        event.content[ModelKey.roomIds]! as List,
      );
      final prevContent =
          event.unsigned?['prev_content'] as Map<String, Object?>?;
      final prevRoomIds =
          prevContent != null && prevContent[ModelKey.roomIds] is List
          ? List<String>.from(prevContent[ModelKey.roomIds] as List)
          : [];
      final newRoomIds = roomIds
          .where((id) => !prevRoomIds.contains(id))
          .toList();

      for (final roomId in newRoomIds) {
        dataService.updateDispatcher.sendActivityAnalyticsUpdate(roomId);
      }
    }
  }

  void _onLemmaInfoEvents(List<MatrixEvent> events) {
    for (final event in events) {
      if (event.stateKey == null) continue;
      final cID = ConstructIdentifier.fromString(event.stateKey!);
      if (cID == null) continue;

      final update = UserSetLemmaInfo.fromJson(event.content);
      dataService.updateDispatcher.sendLemmaInfoUpdate(cID, update);
    }
  }

  Future<void> _onBlockedConstructEvents(List<MatrixEvent> events) async {
    for (final event in events) {
      final current = AnalyticsSettingsModel.fromJson(event.content);
      final prevContent =
          event.unsigned?['prev_content'] as Map<String, Object?>?;
      final prev = prevContent != null
          ? AnalyticsSettingsModel.fromJson(prevContent)
          : null;

      final newBlocked = current.blockedConstructs;
      final prevBlocked = prev?.blockedConstructs ?? {};

      final newlyBlocked = newBlocked.where((c) => !prevBlocked.contains(c));
      for (final constructId in newlyBlocked) {
        await dataService.updateDispatcher.sendBlockedConstructUpdate(
          constructId,
        );
      }
    }
  }

  Future<void> waitForSync(String analyticsRoomId) async {
    await client.onSync.stream.firstWhere((update) {
      final roomUpdate = update.rooms?.join?[analyticsRoomId];
      if (roomUpdate == null) return false;

      final hasAnalyticsEvent =
          roomUpdate.timeline?.events?.any(
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
