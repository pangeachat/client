import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_data/analytics_database.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_database_builder.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_service.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_stream_service.dart';
import 'package:fluffychat/pangea/analytics_data/construct_merge_table.dart';
import 'package:fluffychat/pangea/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_event.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_repo.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/user/analytics_profile_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _AnalyticsClient {
  final Client client;
  final AnalyticsDatabase database;

  _AnalyticsClient({
    required this.client,
    required this.database,
  });
}

class AnalyticsStreamUpdate {
  final int points;
  final String? targetID;

  AnalyticsStreamUpdate({
    this.points = 0,
    this.targetID,
  });
}

class AnalyticsDataService {
  _AnalyticsClient? _analyticsClient;
  StreamSubscription? _serverAnalyticsUpdateListener;

  late final AnalyticsUpdateStreamService streamService;
  late final AnalyticsUpdateService updateService;

  Completer<void> _initCompleter = Completer<void>();

  AnalyticsDataService(Client client) {
    streamService = AnalyticsUpdateStreamService(this);
    updateService = AnalyticsUpdateService(this);
    _initDatabase(client).then((_) => _addListeners());
  }

  DerivedAnalyticsDataModel? _cachedDerivedStats;

  _AnalyticsClient get _analyticsClientGetter {
    if (_analyticsClient == null) {
      throw Exception(
        'Analytics database is not initialized. Call initDatabase() first.',
      );
    }
    return _analyticsClient!;
  }

  bool get isInitializing => !_initCompleter.isCompleted;

  Room? get _analyticsRoom {
    final l2 = MatrixState.pangeaController.userController.userL2;
    if (l2 == null) {
      return null;
    }
    return _analyticsClient?.client.analyticsRoomLocal(l2);
  }

  Future<Room?> getAnalyticsRoom(LanguageModel l2) =>
      _analyticsClientGetter.client.getMyAnalyticsRoom(l2);

  void dispose() {
    _serverAnalyticsUpdateListener?.cancel();
    _serverAnalyticsUpdateListener = null;

    streamService.dispose();
    _closeDatabase();
  }

  void _addListeners() {
    _serverAnalyticsUpdateListener ??= _analyticsClientGetter
        .client.onSync.stream
        .listen(updateServerAnalytics);
  }

  void _clearCache() {
    _cachedDerivedStats = null;
  }

  Future<void> _initDatabase(Client client) async {
    _clearCache();
    await _closeDatabase();

    final database = await analyticsDatabaseBuilder(
      "${client.clientName}_analytics",
    );
    _analyticsClient = _AnalyticsClient(client: client, database: database);

    if (client.isLogged()) {
      await _initAnalytics();
    } else {
      await client.onLoginStateChanged.stream.firstWhere(
        (state) => state == LoginState.loggedIn,
      );
      await _initAnalytics();
    }
  }

  Future<void> _initAnalytics() async {
    try {
      final client = _analyticsClientGetter.client;
      if (client.prevBatch == null) {
        await client.onSync.stream.first;
      }

      final resp = await client.getUserProfile(client.userID!);
      final analyticsProfile =
          AnalyticsProfileModel.fromJson(resp.additionalProperties);

      await updateXPOffset(analyticsProfile.xpOffset ?? 0);
      await _bulkUpdateAnalytics();
      await _initMergeTable();
    } catch (e) {
      Logs().e("Error initializing analytics: $e");
    } finally {
      _initCompleter.complete();
      streamService.sendConstructAnalyticsUpdate(AnalyticsUpdate([]));
    }
  }

  Future<void> _initMergeTable() async {
    final vocab = await _analyticsClientGetter.database
        .getAggregatedConstructs(ConstructTypeEnum.vocab);
    final morph = await _analyticsClientGetter.database
        .getAggregatedConstructs(ConstructTypeEnum.morph);

    ConstructMergeTable.instance.addConstructs(vocab);
    ConstructMergeTable.instance.addConstructs(morph);
  }

  Future<void> reinitialize() async {
    Logs().i("Reinitializing analytics database.");
    _initCompleter = Completer<void>();
    await _initDatabase(_analyticsClientGetter.client);
  }

  Future<void> _closeDatabase() async {
    await _analyticsClient?.database.delete();
    _analyticsClient = null;
    _clearCache();
    ConstructMergeTable.instance.clear();
  }

  int numConstructs(ConstructTypeEnum type) =>
      ConstructMergeTable.instance.uniqueConstructsByType(type);

  Future<DerivedAnalyticsDataModel> get derivedData async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    _cachedDerivedStats ??=
        await _analyticsClientGetter.database.getDerivedStats();
    return _cachedDerivedStats!;
  }

  Future<DateTime?> getLastUpdatedAnalytics() async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    return _analyticsClientGetter.database.getLastEventTimestamp();
  }

  Future<List<OneConstructUse>> getUses({
    int? count,
    String? roomId,
    DateTime? since,
  }) async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    return _analyticsClientGetter.database.getUses(
      count: count,
      roomId: roomId,
      since: since,
    );
  }

  Future<List<OneConstructUse>> getLocalUses() async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    return _analyticsClientGetter.database.getLocalUses();
  }

  Future<int> getLocalConstructCount() async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    return _analyticsClientGetter.database.getLocalConstructCount();
  }

  Future<ConstructUses> getConstructUse(ConstructIdentifier id) async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    final ids = ConstructMergeTable.instance.groupedIds(id);
    return _analyticsClientGetter.database.getConstructUse(ids);
  }

  Future<Map<ConstructIdentifier, ConstructUses>> getConstructUses(
    List<ConstructIdentifier> ids,
  ) async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    final Map<ConstructIdentifier, List<ConstructIdentifier>> request = {};
    for (final id in ids) {
      request[id] = ConstructMergeTable.instance.groupedIds(id);
    }

    return _analyticsClientGetter.database.getConstructUses(request);
  }

  Future<Map<ConstructIdentifier, ConstructUses>> getAggregatedConstructs(
    ConstructTypeEnum type,
  ) async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    final combined =
        await _analyticsClientGetter.database.getAggregatedConstructs(type);

    final stopwatch = Stopwatch()..start();

    final cleaned = <ConstructIdentifier, ConstructUses>{};
    for (final entry in combined) {
      final canonical = ConstructMergeTable.instance.resolve(entry.id);

      // Insert or merge
      final existing = cleaned[canonical];
      if (existing != null) {
        existing.merge(entry);
      } else {
        cleaned[canonical] = entry;
      }
    }

    stopwatch.stop();
    Logs().i(
      "Merging analytics took: ${stopwatch.elapsedMilliseconds} ms, total constructs: ${cleaned.length}",
    );

    return cleaned;
  }

  Future<int> getNewConstructCount(
    List<OneConstructUse> newConstructs,
    ConstructTypeEnum type,
  ) async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    final uses = newConstructs.where((c) => c.constructType == type);
    final Map<ConstructIdentifier, int> constructPoints = {};
    for (final use in uses) {
      constructPoints[use.identifier] ??= 0;
      constructPoints[use.identifier] =
          constructPoints[use.identifier]! + use.xp;
    }

    int newConstructCount = 0;
    for (final entry in constructPoints.entries) {
      final construct = await getConstructUse(entry.key);
      if (construct.points == entry.value) {
        newConstructCount++;
      }
    }

    return newConstructCount;
  }

  Future<ConstructSummary> getLevelUpAnalytics(
    final int lowerLevel,
    final int upperLevel,
    final DateTime? lastLevelUpTimestamp,
  ) async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    final int maxXP =
        DerivedAnalyticsDataModel.calculateXpWithLevel(upperLevel);
    final int minXP =
        DerivedAnalyticsDataModel.calculateXpWithLevel(lowerLevel);

    int diffXP = maxXP - minXP;
    if (diffXP < 0) diffXP = 0;

    // compute construct use of current level
    final List<OneConstructUse> constructUseOfCurrentLevel = [];

    final uses = await getUses(
      since: lastLevelUpTimestamp,
    );

    for (final use in uses) {
      constructUseOfCurrentLevel.add(use);
    }

    // extract construct use message bodies for analytics
    final Map<String, Set<String>> useEventIds = {};
    for (final use in constructUseOfCurrentLevel) {
      if (use.metadata.roomId == null) continue;
      if (use.metadata.eventId == null) continue;
      useEventIds[use.metadata.roomId!] ??= {};
      useEventIds[use.metadata.roomId!]!.add(use.metadata.eventId!);
    }

    final List<Map<String, dynamic>> messages = [];
    for (final entry in useEventIds.entries) {
      final String roomId = entry.key;
      final room = _analyticsClientGetter.client.getRoomById(roomId);
      if (room == null) continue;

      final timeline = await room.getTimeline();
      for (final eventId in entry.value) {
        try {
          final Event? event = await room.getEventById(eventId);
          if (event == null) continue;
          final pangeaMessageEvent = PangeaMessageEvent(
            event: event,
            timeline: timeline,
            ownMessage: room.client.userID == event.senderId,
          );

          final Map<String, String?> entry = {
            "sent": pangeaMessageEvent.originalSent?.text ??
                pangeaMessageEvent.body,
            "written": pangeaMessageEvent.originalWrittenContent,
          };

          messages.add(entry);
        } catch (e, s) {
          ErrorHandler.logError(
            e: e,
            s: s,
            data: {
              'roomId': roomId,
              'eventId': eventId,
            },
          );
          continue;
        }
      }
    }

    final request = ConstructSummaryRequest(
      constructs: constructUseOfCurrentLevel,
      messages: messages,
      userL1: MatrixState.pangeaController.userController.userL1!.langCodeShort,
      userL2: MatrixState.pangeaController.userController.userL2!.langCodeShort,
      upperLevel: upperLevel,
      lowerLevel: lowerLevel,
    );

    final response = await ConstructRepo.generateConstructSummary(request);
    final ConstructSummary summary = response.summary;

    summary.levelVocabConstructs = numConstructs(ConstructTypeEnum.vocab);
    summary.levelGrammarConstructs = numConstructs(ConstructTypeEnum.morph);

    // final Room? analyticsRoom = await _client.getMyAnalyticsRoom(_l2!);
    // if (analyticsRoom == null) {
    //   throw "Analytics room not found for user";
    // }

    // // don't await this, just return the original response
    // analyticsRoom.setLevelUpSummary(summary);
    return summary;
  }

  Future<void> updateXPOffset(int offset) async {
    await _analyticsClientGetter.database.updateXPOffset(offset);
    _clearCache();
  }

  Future<void> updateLocalAnalytics(
    AnalyticsUpdate update,
  ) async {
    _clearCache();

    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    await _analyticsClientGetter.database.updateLocalAnalytics(
      update.newConstructs,
    );

    ConstructMergeTable.instance.addConstructsByUses(update.newConstructs);
  }

  Future<void> updateServerAnalytics(
    SyncUpdate update,
  ) async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    final analyticsRoom = _analyticsRoom;
    if (analyticsRoom == null) return;

    final events =
        update.rooms?.join?[analyticsRoom.id]?.timeline?.events?.where(
      (e) =>
          e.type == PangeaEventTypes.construct &&
          e.senderId == _analyticsClientGetter.client.userID,
    );

    if (events == null || events.isEmpty) {
      return;
    }

    final constructEvents = events
        .map(
          (e) => ConstructAnalyticsEvent(
            event: Event.fromMatrixEvent(e, analyticsRoom),
          ),
        )
        .where((e) => e.event.status == EventStatus.synced)
        .toList();

    _clearCache();
    await _analyticsClientGetter.database
        .updateServerAnalytics(constructEvents);

    for (final event in constructEvents) {
      ConstructMergeTable.instance.addConstructsByUses(event.content.uses);
    }
  }

  Future<void> _bulkUpdateAnalytics() async {
    Logs().i("Starting bulk update of server analytics.");
    final Room? analyticsRoom = _analyticsRoom;
    if (analyticsRoom == null) return;

    final analytics = _analyticsClientGetter;
    final lastUpdated = await analytics.database.getLastEventTimestamp();

    final events = await analyticsRoom.getAnalyticsEvents(
      userId: analytics.client.userID!,
      since: lastUpdated,
    );

    if (events == null || events.isEmpty) return;

    _clearCache();
    await analytics.database.updateServerAnalytics(events);
  }

  Future<void> clearLocalAnalytics() async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }
    await _analyticsClientGetter.database.clearLocalConstructData();
  }
}
