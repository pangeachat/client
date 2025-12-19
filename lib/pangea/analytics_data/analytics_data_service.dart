import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_data/analytics_database.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_database_builder.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_sync_controller.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_service.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_stream_service.dart';
import 'package:fluffychat/pangea/analytics_data/construct_merge_table.dart';
import 'package:fluffychat/pangea/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/analytics_data/level_up_analytics_service.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_event.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/user/analytics_profile_model.dart';

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

  late final AnalyticsUpdateStreamService streamService;
  late final AnalyticsUpdateService updateService;
  late final LevelUpAnalyticsService levelUpService;
  AnalyticsSyncController? _syncController;

  Completer<void> _initCompleter = Completer<void>();

  AnalyticsDataService(Client client) {
    streamService = AnalyticsUpdateStreamService(this);
    updateService = AnalyticsUpdateService(this);
    levelUpService = LevelUpAnalyticsService(
      client: client,
      ensureInitialized: () => _ensureInitialized(),
      getUses: (since) => getUses(since: since),
    );
    _initDatabase(client);
  }

  int _cacheVersion = 0;
  int _derivedCacheVersion = -1;
  DerivedAnalyticsDataModel? _cachedDerivedStats;

  _AnalyticsClient get _analyticsClientGetter {
    assert(_analyticsClient != null);
    return _analyticsClient!;
  }

  bool get isInitializing => !_initCompleter.isCompleted;

  Future<Room?> getAnalyticsRoom(LanguageModel l2) =>
      _analyticsClientGetter.client.getMyAnalyticsRoom(l2);

  void dispose() {
    _syncController?.dispose();
    streamService.dispose();
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
      final client = _analyticsClientGetter.client;
      if (client.prevBatch == null) {
        await client.onSync.stream.first;
      }

      _invalidateCaches();
      final resp = await client.getUserProfile(client.userID!);
      final analyticsProfile =
          AnalyticsProfileModel.fromJson(resp.additionalProperties);

      _syncController?.dispose();
      _syncController = AnalyticsSyncController(
        client: client,
        dataService: this,
      );

      await updateXPOffset(analyticsProfile.xpOffset ?? 0);

      await _syncController!.bulkUpdate();
      _syncController!.start();

      await _initMergeTable();
    } catch (e) {
      Logs().e("Error initializing analytics: $e");
    } finally {
      Logs().i("Analytics database initialized.");
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
    await _clearDatabase();
    await _initDatabase(_analyticsClientGetter.client);
  }

  Future<void> _clearDatabase() async {
    await _analyticsClient?.database.clear();
    _invalidateCaches();
    ConstructMergeTable.instance.clear();
  }

  Future<void> _closeDatabase() async {
    await _analyticsClient?.database.delete();
    _analyticsClient = null;
    _invalidateCaches();
    ConstructMergeTable.instance.clear();
  }

  Future<void> _ensureInitialized() =>
      _initCompleter.isCompleted ? Future.value() : _initCompleter.future;

  int numConstructs(ConstructTypeEnum type) =>
      ConstructMergeTable.instance.uniqueConstructsByType(type);

  Future<void> waitForSync() async {
    await _syncController?.syncStream.stream.first;
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
    return _analyticsClientGetter.database.getUses(
      count: count,
      roomId: roomId,
      since: since,
    );
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
    final ids = ConstructMergeTable.instance.groupedIds(id);
    return _analyticsClientGetter.database.getConstructUse(ids);
  }

  Future<Map<ConstructIdentifier, ConstructUses>> getConstructUses(
    List<ConstructIdentifier> ids,
  ) async {
    await _ensureInitialized();
    final Map<ConstructIdentifier, List<ConstructIdentifier>> request = {};
    for (final id in ids) {
      request[id] = ConstructMergeTable.instance.groupedIds(id);
    }

    return _analyticsClientGetter.database.getConstructUses(request);
  }

  Future<Map<ConstructIdentifier, ConstructUses>> getAggregatedConstructs(
    ConstructTypeEnum type,
  ) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
    final uses = newConstructs.where((c) => c.constructType == type);
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

  Future<void> updateLocalAnalytics(
    AnalyticsUpdate update,
  ) async {
    _invalidateCaches();
    await _ensureInitialized();
    await _analyticsClientGetter.database.updateLocalAnalytics(
      update.newConstructs,
    );

    ConstructMergeTable.instance.addConstructsByUses(update.newConstructs);
  }

  Future<void> updateServerAnalytics(
    List<ConstructAnalyticsEvent> events,
  ) async {
    _invalidateCaches();
    await _analyticsClientGetter.database.updateServerAnalytics(events);
  }

  Future<void> clearLocalAnalytics() async {
    _invalidateCaches();
    await _ensureInitialized();
    await _analyticsClientGetter.database.clearLocalConstructData();
  }
}
