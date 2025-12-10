// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:fluffychat/pangea/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_event.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';

import 'package:matrix/src/database/database_file_storage_stub.dart'
    if (dart.library.io) 'package:matrix/src/database/database_file_storage_io.dart';
import 'package:matrix/src/database/indexeddb_box.dart'
    if (dart.library.io) 'package:matrix/src/database/sqflite_box.dart';

class AnalyticsDatabase with DatabaseFileStorage {
  final String name;

  late BoxCollection _collection;
  late Box<String> _lastEventTimestampBox;
  late Box<List> _serverConstructsBox;
  late Box<Map> _aggregatedServerConstructsBox;
  late Box<List> _localConstructsBox;
  late Box<Map> _aggregatedLocalConstructsBox;
  late Box<Map> _derivedServerStatsBox;
  late Box<Map> _derivedLocalStatsBox;

  /// Key is eventID as String
  static const String _serverConstructsBoxName = 'box_server_constructs';

  /// Key is Tuple of construct lemma, type, and category
  static const String _aggregatedServerConstructsBoxName =
      'box_aggregated_server_constructs';

  static const String _localConstructsBoxName = 'box_local_constructs';

  static const String _aggregatedLocalConstructsBoxName =
      'box_aggregated_local_constructs';

  static const String _derivedServerStatsBoxName = 'box_derived_server_stats';

  static const String _derivedLocalStatsBoxName = 'box_derived_local_stats';

  static const String _lastEventTimestampBoxName = 'box_last_event_timestamp';

  Database? database;

  /// Custom IdbFactory used to create the indexedDB. On IO platforms it would
  /// lead to an error to import "dart:indexed_db" so this is dynamically
  /// typed.
  final dynamic idbFactory;

  /// Custom SQFlite Database Factory used for high level operations on IO
  /// like delete. Set it if you want to use sqlite FFI.
  final DatabaseFactory? sqfliteFactory;

  static Future<AnalyticsDatabase> init(
    String name, {
    Database? database,
    dynamic idbFactory,
    DatabaseFactory? sqfliteFactory,
    Uri? fileStorageLocation,
    Duration? deleteFilesAfterDuration,
  }) async {
    final analyticsDatabase = AnalyticsDatabase._(
      name,
      database: database,
      idbFactory: idbFactory,
      sqfliteFactory: sqfliteFactory,
      fileStorageLocation: fileStorageLocation,
      deleteFilesAfterDuration: deleteFilesAfterDuration,
    );
    await analyticsDatabase.open();
    return analyticsDatabase;
  }

  AnalyticsDatabase._(
    this.name, {
    this.database,
    this.idbFactory,
    this.sqfliteFactory,
    Uri? fileStorageLocation,
    Duration? deleteFilesAfterDuration,
  }) {
    this.fileStorageLocation = fileStorageLocation;
    this.deleteFilesAfterDuration = deleteFilesAfterDuration;
  }

  Future<void> open() async {
    _collection = await BoxCollection.open(
      name,
      {
        _serverConstructsBoxName,
        _aggregatedServerConstructsBoxName,
        _lastEventTimestampBoxName,
        _localConstructsBoxName,
        _aggregatedLocalConstructsBoxName,
        _derivedServerStatsBoxName,
        _derivedLocalStatsBoxName,
      },
      sqfliteDatabase: database,
      sqfliteFactory: sqfliteFactory,
      idbFactory: idbFactory,
      version: MatrixSdkDatabase.version,
    );

    _serverConstructsBox = _collection.openBox<List>(
      _serverConstructsBoxName,
    );
    _aggregatedServerConstructsBox = _collection.openBox<Map>(
      _aggregatedServerConstructsBoxName,
    );
    _lastEventTimestampBox = _collection.openBox<String>(
      _lastEventTimestampBoxName,
    );
    _localConstructsBox = _collection.openBox<List>(
      _localConstructsBoxName,
    );
    _aggregatedLocalConstructsBox = _collection.openBox<Map>(
      _aggregatedLocalConstructsBoxName,
    );
    _derivedServerStatsBox = _collection.openBox<Map>(
      _derivedServerStatsBoxName,
    );
    _derivedLocalStatsBox = _collection.openBox<Map>(
      _derivedLocalStatsBoxName,
    );
  }

  Future<void> delete() async {
    // database?.path is null on web
    await _collection.deleteDatabase(
      database?.path ?? name,
      sqfliteFactory ?? idbFactory,
    );
  }

  Future<void> _transaction(Future<void> Function() action) =>
      _collection.transaction(action);

  Future<DateTime?> getLastEventTimestamp() async {
    final timestampString =
        await _lastEventTimestampBox.get('last_event_timestamp');
    if (timestampString == null) return null;
    return DateTime.parse(timestampString);
  }

  Future<DerivedAnalyticsDataModel> _getDerivedServerStats() async {
    final raw = await _derivedServerStatsBox.get('derived_stats');
    return raw == null
        ? DerivedAnalyticsDataModel()
        : DerivedAnalyticsDataModel.fromJson(
            Map<String, dynamic>.from(raw),
          );
  }

  Future<DerivedAnalyticsDataModel> _getDerivedLocalStats() async {
    final raw = await _derivedLocalStatsBox.get('derived_stats');
    return raw == null
        ? DerivedAnalyticsDataModel()
        : DerivedAnalyticsDataModel.fromJson(
            Map<String, dynamic>.from(raw),
          );
  }

  Future<DerivedAnalyticsDataModel> getDerivedStats() async {
    DerivedAnalyticsDataModel server = DerivedAnalyticsDataModel();
    DerivedAnalyticsDataModel local = DerivedAnalyticsDataModel();
    await _transaction(() async {
      server = await _getDerivedServerStats();
      local = await _getDerivedLocalStats();
    });
    return server.merge(local);
  }

  Future<void> clearLocalConstructData() async {
    await _transaction(() async {
      await _localConstructsBox.clear();
      await _aggregatedLocalConstructsBox.clear();
      await _derivedLocalStatsBox.clear();
    });
  }

  Future<Map<String, ConstructUses>> getCombinedAggregates() async {
    Map<String, ConstructUses> combined = {};
    await _transaction(() async {
      final serverKeys = await _aggregatedServerConstructsBox.getAllKeys();
      final serverValues =
          await _aggregatedServerConstructsBox.getAll(serverKeys);
      final serverConstructs = serverValues
          .map((e) => ConstructUses.fromJson(Map<String, dynamic>.from(e!)))
          .toList();

      final serverAgg = Map.fromIterables(
        serverKeys,
        serverConstructs,
      );

      final localKeys = await _aggregatedLocalConstructsBox.getAllKeys();
      final localValues = await _aggregatedLocalConstructsBox.getAll(localKeys);
      final localConstructs = localValues
          .map((e) => ConstructUses.fromJson(Map<String, dynamic>.from(e!)))
          .toList();

      final localAgg = Map.fromIterables(
        localKeys,
        localConstructs,
      );

      combined = Map<String, ConstructUses>.from(serverAgg);
      for (final entry in localAgg.entries) {
        final key = entry.key;
        final localModel = entry.value;

        if (combined.containsKey(key)) {
          final serverModel = combined[key]!;

          // Combine uses
          serverModel.uses.addAll(localModel.uses);

          // Update lastUsed
          final localLastUsed = localModel.lastUsed;
          final lastUsed = serverModel.lastUsed;
          if (lastUsed == null ||
              (localLastUsed != null && localLastUsed.isAfter(lastUsed))) {
            serverModel.setLastUsed(localLastUsed!);
          }
        } else {
          combined[key] = localModel;
        }
      }
    });
    return combined;
  }

  /// Group uses by aggregate key
  Map<String, List<OneConstructUse>> _groupUses(
    List<OneConstructUse> uses,
  ) {
    final Map<String, List<OneConstructUse>> grouped = {};
    for (final u in uses) {
      final key = TupleKey(
        u.lemma,
        u.constructType.name,
        u.category,
      ).toString();
      (grouped[key] ??= []).add(u);
    }
    return grouped;
  }

  Map<String, ConstructUses> _aggregateConstructs(
    Map<String, List<OneConstructUse>> groups,
    Map<String, Map<dynamic, dynamic>?> existingRaw,
  ) {
    final Map<String, ConstructUses> updates = {};

    for (final entry in groups.entries) {
      final key = entry.key;
      final usesForKey = entry.value;
      final raw = existingRaw[key];

      ConstructUses model;

      if (raw is Map<String, dynamic>) {
        model = ConstructUses.fromJson(raw);
      } else {
        final u = usesForKey.first;
        model = ConstructUses(
          uses: [],
          constructType: u.constructType,
          lemma: u.lemma,
          category: u.category,
        );
      }

      for (final u in usesForKey) {
        model.uses.add(u);
        model.setLastUsed(u.timeStamp);
      }

      updates[key] = model;
    }

    return updates;
  }

  Future<Map<String, ConstructUses>> _aggregateFromBox(
    Box box,
    Map<String, List<OneConstructUse>> grouped,
  ) async {
    final existingRaw = <String, Map<dynamic, dynamic>?>{};
    for (final key in grouped.keys) {
      existingRaw[key] = await box.get(key);
    }
    return _aggregateConstructs(grouped, existingRaw);
  }

  Future<void> updateXPOffset(int offset) {
    return _transaction(() async {
      final serverStats = await _getDerivedServerStats();
      final localStats = await _getDerivedLocalStats();

      final updatedServerStats = serverStats.copyWith(
        offset: offset,
      );
      final updatedLocalStats = localStats.copyWith(
        offset: offset,
      );

      await _derivedServerStatsBox.put(
        'derived_stats',
        updatedServerStats.toJson(),
      );
      await _derivedLocalStatsBox.put(
        'derived_stats',
        updatedLocalStats.toJson(),
      );
    });
  }

  Future<void> updateServerAnalytics(
    List<ConstructAnalyticsEvent> events,
  ) async {
    if (events.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    await _transaction(() async {
      final lastUpdated = await getLastEventTimestamp();
      final derivedData = await _getDerivedServerStats();
      DateTime mostRecent = lastUpdated ?? events.first.event.originServerTs;

      final existingKeys = (await _serverConstructsBox.getAllKeys()).toSet();

      final List<OneConstructUse> aggregatedUses = [];
      final Map<String, List<OneConstructUse>> pendingWrites = {};

      for (final event in events) {
        final ts = event.event.originServerTs;

        if (lastUpdated != null && ts.isBefore(lastUpdated)) continue;
        if (existingKeys.contains(event.event.eventId)) continue;

        if (ts.isAfter(mostRecent)) mostRecent = ts;

        pendingWrites[event.event.eventId] = event.content.uses;
        aggregatedUses.addAll(event.content.uses);
      }

      if (pendingWrites.isEmpty) {
        return;
      }

      // Write events sequentially
      for (final e in pendingWrites.entries) {
        _serverConstructsBox.put(
          e.key,
          e.value.map((u) => u.toJson()).toList(),
        );
      }

      // Update aggregates
      final aggUpdates = await _aggregateFromBox(
        _aggregatedServerConstructsBox,
        _groupUses(aggregatedUses),
      );

      for (final entry in aggUpdates.entries) {
        await _aggregatedServerConstructsBox.put(
          entry.key,
          entry.value.toJson(),
        );
      }

      // Update derived stats
      final updatedDerivedStats = derivedData.update(aggregatedUses);
      await _derivedServerStatsBox.put(
        'derived_stats',
        updatedDerivedStats.toJson(),
      );

      // Update timestamp
      await _lastEventTimestampBox.put(
        'last_event_timestamp',
        mostRecent.toIso8601String(),
      );
    });

    stopwatch.stop();
    Logs().i(
      "Server analytics update took ${stopwatch.elapsedMilliseconds} ms",
    );
  }

  Future<void> updateLocalAnalytics(
    List<OneConstructUse> uses,
  ) async {
    if (uses.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    await _transaction(() async {
      // Store local constructs
      final key = DateTime.now().toIso8601String();
      _localConstructsBox.put(
        key,
        uses.map((u) => u.toJson()).toList(),
      );

      // Update aggregates
      final aggUpdates = await _aggregateFromBox(
        _aggregatedLocalConstructsBox,
        _groupUses(uses),
      );
      for (final entry in aggUpdates.entries) {
        await _aggregatedLocalConstructsBox.put(
          entry.key,
          entry.value.toJson(),
        );
      }
    });

    // Update derived stats
    final derivedData = await _getDerivedLocalStats();
    final updatedDerivedStats = derivedData.update(uses);
    await _derivedLocalStatsBox.put(
      'derived_stats',
      updatedDerivedStats.toJson(),
    );

    stopwatch.stop();
    Logs().i("Local analytics update took ${stopwatch.elapsedMilliseconds} ms");
  }
}
