import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_data/analytics_database.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_database_builder.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_sync_controller.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_events.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_service.dart';
import 'package:fluffychat/pangea/analytics_data/construct_merge_table.dart';
import 'package:fluffychat/pangea/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/analytics_data/level_up_analytics_service.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_event.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_settings/analytics_settings_extension.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
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
  final ConstructIdentifier? blockedConstruct;
  final String? targetID;

  AnalyticsStreamUpdate({
    this.points = 0,
    this.blockedConstruct,
    this.targetID,
  });
}

class AnalyticsDataService {
  _AnalyticsClient? _analyticsClient;

  late final AnalyticsUpdateDispatcher updateDispatcher;
  late final AnalyticsUpdateService updateService;
  late final LevelUpAnalyticsService levelUpService;
  AnalyticsSyncController? _syncController;
  final ConstructMergeTable _mergeTable = ConstructMergeTable();

  Completer<void> initCompleter = Completer<void>();

  AnalyticsDataService(Client client) {
    updateDispatcher = AnalyticsUpdateDispatcher(this);
    updateService = AnalyticsUpdateService(this);
    levelUpService = LevelUpAnalyticsService(
      client: client,
      ensureInitialized: () => _ensureInitialized(),
      dataService: this,
    );
    _initDatabase(client);
  }

  static const int _morphUnlockXP = 30;

  int _cacheVersion = 0;
  int _derivedCacheVersion = -1;
  DerivedAnalyticsDataModel? _cachedDerivedStats;

  _AnalyticsClient get _analyticsClientGetter {
    assert(_analyticsClient != null);
    return _analyticsClient!;
  }

  bool get isInitializing => !initCompleter.isCompleted;

  Future<Room?> getAnalyticsRoom(LanguageModel l2) =>
      _analyticsClientGetter.client.getMyAnalyticsRoom(l2);

  void dispose() {
    _syncController?.dispose();
    updateDispatcher.dispose();
    _closeDatabase();
  }

  void _invalidateCaches() {
    _cacheVersion++;
    _cachedDerivedStats = null;
  }

  Future<void> _initDatabase(Client client) async {
    _invalidateCaches();

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
      Logs().i("Initializing analytics database.");
      final client = _analyticsClientGetter.client;
      if (client.prevBatch == null) {
        await client.onSync.stream.first;
      }

      _invalidateCaches();
      final analyticsUserId = await _analyticsClientGetter.database.getUserID();
      if (analyticsUserId != client.userID) {
        await _clearDatabase();
        await _analyticsClientGetter.database.updateUserID(client.userID!);
      }

      final resp = await client.getUserProfile(client.userID!);
      final analyticsProfile =
          AnalyticsProfileModel.fromJson(resp.additionalProperties);

      _syncController?.dispose();
      _syncController = AnalyticsSyncController(
        client: client,
        dataService: this,
      );
      await _syncController!.bulkUpdate();

      final vocab = await getAggregatedConstructs(ConstructTypeEnum.vocab);
      final morphs = await getAggregatedConstructs(ConstructTypeEnum.morph);
      final constructs = [...vocab.values, ...morphs.values];
      final totalXP = constructs.fold(0, (total, c) => total + c.points);
      await _analyticsClientGetter.database.updateDerivedStats(
        DerivedAnalyticsDataModel(
          totalXP: totalXP,
          offset: analyticsProfile.xpOffset ?? 0,
        ),
      );

      _syncController!.start();

      await _initMergeTable();
    } catch (e, s) {
      Logs().e("Error initializing analytics: $e, $s");
    } finally {
      Logs().i("Analytics database initialized.");
      initCompleter.complete();
      updateDispatcher.sendConstructAnalyticsUpdate(AnalyticsUpdate([]));
    }
  }

  Future<void> _initMergeTable() async {
    final vocab = await _analyticsClientGetter.database
        .getAggregatedConstructs(ConstructTypeEnum.vocab);
    final morph = await _analyticsClientGetter.database
        .getAggregatedConstructs(ConstructTypeEnum.morph);

    final blocked = blockedConstructs;
    _mergeTable.addConstructs(vocab, blocked);
    _mergeTable.addConstructs(morph, blocked);
  }

  Future<void> reinitialize() async {
    Logs().i("Reinitializing analytics database.");
    initCompleter = Completer<void>();
    await _clearDatabase();
    await _initDatabase(_analyticsClientGetter.client);
  }

  Future<void> _clearDatabase() async {
    await _analyticsClient?.database.clear();
    _invalidateCaches();
    _mergeTable.clear();
  }

  Future<void> _closeDatabase() async {
    await _analyticsClient?.database.delete();
    _analyticsClient = null;
    _invalidateCaches();
    _mergeTable.clear();
  }

  Future<void> _ensureInitialized() =>
      initCompleter.isCompleted ? Future.value() : initCompleter.future;

  int numConstructs(ConstructTypeEnum type) =>
      _mergeTable.uniqueConstructsByType(type);

  bool hasUsedConstruct(ConstructIdentifier id) =>
      _mergeTable.constructUsed(id);

  int uniqueConstructsByType(ConstructTypeEnum type) =>
      _mergeTable.uniqueConstructsByType(type);

  Set<ConstructIdentifier> get blockedConstructs {
    final analyticsRoom = _analyticsClientGetter.client.analyticsRoomLocal();
    return analyticsRoom?.blockedConstructs ?? {};
  }

  Future<void> waitForSync(String analyticsRoomID) async {
    await _syncController?.waitForSync(analyticsRoomID);
  }

  Future<DerivedAnalyticsDataModel> get derivedData async {
    await _ensureInitialized();

    if (_cachedDerivedStats == null || _derivedCacheVersion != _cacheVersion) {
      _cachedDerivedStats =
          await _analyticsClientGetter.database.getDerivedStats();
      _derivedCacheVersion = _cacheVersion;
    }

    return _cachedDerivedStats!;
  }

  Future<DateTime?> getLastUpdatedAnalytics() async {
    return _analyticsClientGetter.database.getLastEventTimestamp();
  }

  Future<List<OneConstructUse>> getUses({
    int? count,
    String? roomId,
    DateTime? since,
  }) async {
    await _ensureInitialized();
    final uses = await _analyticsClientGetter.database.getUses(
      count: count,
      roomId: roomId,
      since: since,
    );

    final blocked = blockedConstructs;
    final List<OneConstructUse> filtered = [];

    final Map<ConstructIdentifier, DateTime?> cappedLastUseCache = {};
    for (final use in uses) {
      if (blocked.contains(use.identifier)) continue;
      if (!cappedLastUseCache.containsKey(use.identifier)) {
        final constructs = await getConstructUse(use.identifier);
        cappedLastUseCache[use.identifier] = constructs.cappedLastUse;
      }
      final cappedLastUse = cappedLastUseCache[use.identifier];
      if (cappedLastUse != null && use.timeStamp.isAfter(cappedLastUse)) {
        continue;
      }
      filtered.add(use);
    }

    return filtered;
  }

  Future<List<OneConstructUse>> getLocalUses() async {
    await _ensureInitialized();
    return _analyticsClientGetter.database.getLocalUses();
  }

  Future<int> getLocalConstructCount() async {
    await _ensureInitialized();
    return _analyticsClientGetter.database.getLocalConstructCount();
  }

  Future<ConstructUses> getConstructUse(ConstructIdentifier id) async {
    await _ensureInitialized();
    final blocked = blockedConstructs;
    final ids = _mergeTable.groupedIds(_mergeTable.resolve(id), blocked);
    if (ids.isEmpty) {
      return ConstructUses(
        uses: [],
        constructType: id.type,
        lemma: id.lemma,
        category: id.category,
      );
    }

    return _analyticsClientGetter.database.getConstructUse(ids);
  }

  Future<Map<ConstructIdentifier, ConstructUses>> getConstructUses(
    List<ConstructIdentifier> ids,
  ) async {
    await _ensureInitialized();
    final Map<ConstructIdentifier, List<ConstructIdentifier>> request = {};
    final blocked = blockedConstructs;
    for (final id in ids) {
      if (blocked.contains(id)) continue;
      request[id] = _mergeTable.groupedIds(_mergeTable.resolve(id), blocked);
    }

    return _analyticsClientGetter.database.getConstructUses(request);
  }

  Future<Map<ConstructIdentifier, ConstructUses>> getAggregatedConstructs(
    ConstructTypeEnum type,
  ) async {
    final combined =
        await _analyticsClientGetter.database.getAggregatedConstructs(type);

    final stopwatch = Stopwatch()..start();

    final cleaned = <ConstructIdentifier, ConstructUses>{};
    final blocked = blockedConstructs;
    for (final entry in combined) {
      final canonical = _mergeTable.resolve(entry.id);

      // Insert or merge
      final existing = cleaned[canonical];
      if (existing != null) {
        existing.merge(entry);
      } else if (!blocked.contains(canonical)) {
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
    await _ensureInitialized();
    final blocked = blockedConstructs;
    final uses = newConstructs
        .where(
          (c) => c.constructType == type && !blocked.contains(c.identifier),
        )
        .toList();

    final Map<ConstructIdentifier, int> constructPoints = {};
    for (final use in uses) {
      constructPoints[use.identifier] ??= 0;
      constructPoints[use.identifier] =
          constructPoints[use.identifier]! + use.xp;
    }

    final constructs = await getConstructUses(constructPoints.keys.toList());

    int newConstructCount = 0;
    for (final entry in constructPoints.entries) {
      final construct = constructs[entry.key]!;
      if (construct.points == entry.value) {
        newConstructCount++;
      }
    }

    return newConstructCount;
  }

  Future<void> updateXPOffset(int offset) async {
    _invalidateCaches();
    await _analyticsClientGetter.database.updateXPOffset(offset);
  }

  Future<List<AnalyticsUpdateEvent>> updateLocalAnalytics(
    AnalyticsUpdate update,
  ) async {
    final events = <AnalyticsUpdateEvent>[];
    final updateIds = update.addedConstructs.map((c) => c.identifier).toList();

    final prevData = await derivedData;
    final prevConstructs = await getConstructUses(updateIds);

    _invalidateCaches();
    await _ensureInitialized();

    final blocked = blockedConstructs;
    _mergeTable.addConstructsByUses(update.addedConstructs, blocked);
    await _analyticsClientGetter.database.updateLocalAnalytics(
      update.addedConstructs,
    );

    final newConstructs = await getConstructUses(updateIds);

    int points = 0;
    if (update.blockedConstruct == null || updateIds.isNotEmpty) {
      for (final id in updateIds) {
        final prevPoints = prevConstructs[id]?.points ?? 0;
        final newPoints = newConstructs[id]?.points ?? 0;
        points += (newPoints - prevPoints);
      }
      events.add(XPGainedEvent(points, update.targetID));
    }

    final newData = prevData.copyWith(totalXP: prevData.totalXP + points);
    await _analyticsClientGetter.database.updateDerivedStats(newData);

    // Update public profile each time that new analytics are added.
    // If the level hasn't changed, this will not send an update to the server.
    // Do this on all updates (not just on level updates) to account for cases
    // of target language updates being missed (https://github.com/pangeachat/client/issues/2006)
    MatrixState.pangeaController.userController.updateAnalyticsProfile(
      level: newData.level,
    );

    if (newData.level > prevData.level) {
      events.add(LevelUpEvent(prevData.level, newData.level));
    } else if (newData.level < prevData.level) {
      final lowerLevelXP = DerivedAnalyticsDataModel.calculateXpWithLevel(
        prevData.level,
      );

      final offset = lowerLevelXP - newData.totalXP;
      await MatrixState.pangeaController.userController.addXPOffset(offset);
      await updateXPOffset(
        MatrixState.pangeaController.userController.analyticsProfile!.xpOffset!,
      );
    }

    final newUnlockedMorphs = updateIds.where((id) {
      if (id.type != ConstructTypeEnum.morph) return false;
      final prevPoints = prevConstructs[id]?.points ?? 0;
      final newPoints = newConstructs[id]?.points ?? 0;
      return prevPoints < _morphUnlockXP && newPoints >= _morphUnlockXP;
    }).toSet();

    if (newUnlockedMorphs.isNotEmpty) {
      events.add(MorphUnlockedEvent(newUnlockedMorphs));
    }

    if (update.blockedConstruct != null) {
      events.add(ConstructBlockedEvent(update.blockedConstruct!));
    }

    return events;
  }

  Future<void> updateServerAnalytics(
    List<ConstructAnalyticsEvent> events,
  ) async {
    _invalidateCaches();
    final blocked = blockedConstructs;
    for (final event in events) {
      _mergeTable.addConstructsByUses(
        event.content.uses,
        blocked,
      );
    }
    await _analyticsClientGetter.database.updateServerAnalytics(events);
  }

  Future<void> updateBlockedConstructs(
    ConstructIdentifier constructId,
  ) async {
    await _ensureInitialized();
    _mergeTable.removeConstruct(constructId);

    final construct =
        await _analyticsClientGetter.database.getConstructUse([constructId]);

    final derived = await derivedData;
    final newXP = derived.totalXP - construct.points;
    final newLevel = DerivedAnalyticsDataModel.calculateLevelWithXp(newXP);

    await MatrixState.pangeaController.userController.updateAnalyticsProfile(
      level: newLevel,
    );

    await _analyticsClientGetter.database.updateDerivedStats(
      DerivedAnalyticsDataModel(totalXP: newXP),
    );

    _invalidateCaches();
    updateDispatcher.sendConstructAnalyticsUpdate(
      AnalyticsUpdate(
        [],
        blockedConstruct: constructId,
      ),
    );
  }

  Future<void> clearLocalAnalytics() async {
    _invalidateCaches();
    await _ensureInitialized();
    await _analyticsClientGetter.database.clearLocalConstructData();
  }
}
