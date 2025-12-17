// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:async';
import 'dart:math';

import 'package:matrix/matrix.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:fluffychat/pangea/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_event.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';

import 'package:matrix/src/database/database_file_storage_stub.dart'
    if (dart.library.io) 'package:matrix/src/database/database_file_storage_io.dart';
import 'package:matrix/src/database/indexeddb_box.dart'
    if (dart.library.io) 'package:matrix/src/database/sqflite_box.dart';

class AnalyticsDatabase with DatabaseFileStorage {
  final String name;

  late BoxCollection _collection;
  late Box<String> _lastEventTimestampBox;

  late Box<List> _serverConstructsBox;
  late Box<List> _localConstructsBox;
  late Box<Map> _aggregatedServerVocabConstructsBox;
  late Box<Map> _aggregatedLocalVocabConstructsBox;
  late Box<Map> _aggregatedServerMorphConstructsBox;
  late Box<Map> _aggregatedLocalMorphConstructsBox;

  late Box<Map> _derivedServerStatsBox;
  late Box<Map> _derivedLocalStatsBox;

  static const String _serverConstructsBoxName = 'box_server_constructs';

  static const String _localConstructsBoxName = 'box_local_constructs';

  /// Key is Tuple of construct lemma, type, and category
  static const String _aggregatedServerVocabConstructsBoxName =
      'box_aggregated_server_vocab_constructs';

  static const String _aggregatedLocalVocabConstructsBoxName =
      'box_aggregated_local_vocab_constructs';

  static const String _aggregatedServerMorphConstructsBoxName =
      'box_aggregated_server_morph_constructs';

  static const String _aggregatedLocalMorphConstructsBoxName =
      'box_aggregated_local_morph_constructs';

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

  final List<Future> _txnCache = [];

  Future<void> open() async {
    _collection = await BoxCollection.open(
      name,
      {
        _lastEventTimestampBoxName,
        _serverConstructsBoxName,
        _localConstructsBoxName,
        _aggregatedServerVocabConstructsBoxName,
        _aggregatedLocalVocabConstructsBoxName,
        _aggregatedServerMorphConstructsBoxName,
        _aggregatedLocalMorphConstructsBoxName,
        _derivedServerStatsBoxName,
        _derivedLocalStatsBoxName,
      },
      sqfliteDatabase: database,
      sqfliteFactory: sqfliteFactory,
      idbFactory: idbFactory,
      version: MatrixSdkDatabase.version,
    );

    _lastEventTimestampBox = _collection.openBox<String>(
      _lastEventTimestampBoxName,
    );
    _serverConstructsBox = _collection.openBox<List>(
      _serverConstructsBoxName,
    );
    _localConstructsBox = _collection.openBox<List>(
      _localConstructsBoxName,
    );
    _aggregatedServerVocabConstructsBox = _collection.openBox<Map>(
      _aggregatedServerVocabConstructsBoxName,
    );
    _aggregatedLocalVocabConstructsBox = _collection.openBox<Map>(
      _aggregatedLocalVocabConstructsBoxName,
    );
    _aggregatedServerMorphConstructsBox = _collection.openBox<Map>(
      _aggregatedServerMorphConstructsBoxName,
    );
    _aggregatedLocalMorphConstructsBox = _collection.openBox<Map>(
      _aggregatedLocalMorphConstructsBoxName,
    );
    _derivedServerStatsBox = _collection.openBox<Map>(
      _derivedServerStatsBoxName,
    );
    _derivedLocalStatsBox = _collection.openBox<Map>(
      _derivedLocalStatsBoxName,
    );
  }

  Future<void> delete() async {
    Logs().i("Cache length before delete: ${_txnCache.length}");
    final txns = List<Future>.from(_txnCache);
    await Future.wait(txns);
    Logs().i("Cache length after waiting: ${_txnCache.length}");

    await _collection.deleteDatabase(
      database?.path ?? name,
      sqfliteFactory ?? idbFactory,
    );
  }

  Future<void> _transaction(Future<void> Function() action) async {
    final txn = _collection.transaction(action);
    _txnCache.add(txn);
    try {
      await txn;
    } finally {
      _txnCache.remove(txn);
    }
  }

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

  Future<List<OneConstructUse>> getUses({
    int? count,
    String? roomId,
    DateTime? since,
  }) async {
    final List<OneConstructUse> uses = [];
    await _transaction(() async {
      // first, get all of the local (most recent) keys
      final localKeys = await _localConstructsBox.getAllKeys();
      final localValues = await _localConstructsBox.getAll(localKeys);
      final local = Map.fromIterables(
        localKeys,
        localValues,
      ).entries.toList();

      local.sort(
        (a, b) => DateTime.parse(b.key).compareTo(DateTime.parse(a.key)),
      );

      final localUses = [];
      for (final entry in local) {
        // filter by date
        if (since != null && DateTime.parse(entry.key).isBefore(since)) {
          continue;
        }

        final rawUses = entry.value;
        if (rawUses == null) continue;
        for (final raw in rawUses) {
          // filter by count
          if (count != null && uses.length >= count) break;

          final use = OneConstructUse.fromJson(
            Map<String, dynamic>.from(raw),
          );

          // filter by roomID
          if (roomId != null && use.metadata.roomId != roomId) {
            continue;
          }

          localUses.add(use);
          uses.add(use);
        }
        if (count != null && uses.length >= count) break;
      }
      if (count != null && uses.length >= count) return;

      // then get server uses
      final serverKeys = await _serverConstructsBox.getAllKeys();
      serverKeys.sort(
        (a, b) => DateTime.parse(b.split('|')[1])
            .compareTo(DateTime.parse(a.split('|')[1])),
      );
      for (final key in serverKeys) {
        // filter by count
        if (count != null && uses.length >= count) break;
        final rawUses = await _serverConstructsBox.get(key);
        if (rawUses == null) continue;
        for (final raw in rawUses) {
          if (count != null && uses.length >= count) break;
          final use = OneConstructUse.fromJson(
            Map<String, dynamic>.from(raw),
          );

          // filter by roomID
          if (roomId != null && use.metadata.roomId != roomId) {
            continue;
          }

          // filter by date
          if (since != null && use.timeStamp.isBefore(since)) {
            continue;
          }
          uses.add(use);
        }
      }
    });

    return uses.take(count ?? uses.length).toList();
  }

  Future<List<OneConstructUse>> getLocalUses() async {
    final List<OneConstructUse> uses = [];
    await _transaction(() async {
      final localKeys = await _localConstructsBox.getAllKeys();
      final localValues = await _localConstructsBox.getAll(localKeys);
      for (final rawList in localValues) {
        if (rawList == null) continue;
        for (final raw in rawList) {
          final use = OneConstructUse.fromJson(
            Map<String, dynamic>.from(raw),
          );
          uses.add(use);
        }
      }
    });
    return uses;
  }

  Future<int> getLocalConstructCount() async {
    final keys = await _localConstructsBox.getAllKeys();
    return keys.length;
  }

  Future<List<String>> getVocabConstructKeys() async {
    final serverKeys = await _aggregatedServerVocabConstructsBox.getAllKeys();
    final localKeys = await _aggregatedLocalVocabConstructsBox.getAllKeys();
    return [...serverKeys, ...localKeys];
  }

  Future<List<String>> getMorphConstructKeys() async {
    final serverKeys = await _aggregatedServerMorphConstructsBox.getAllKeys();
    final localKeys = await _aggregatedLocalMorphConstructsBox.getAllKeys();
    return [...serverKeys, ...localKeys];
  }

  Future<ConstructUses> getConstructUse(
    List<ConstructIdentifier> ids,
  ) async {
    Logs().i("Construct IDs: ${ids.map((id) => id.string).toList()}");
    assert(ids.isNotEmpty);

    final construct = ConstructUses(
      uses: [],
      constructType: ids.first.type,
      lemma: ids.first.lemma,
      category: ids.first.category,
    );

    await _transaction(() async {
      for (final id in ids) {
        final key = id.storageKey;

        ConstructUses? server;
        ConstructUses? local;
        if (id.type == ConstructTypeEnum.vocab) {
          final serverRaw = await _aggregatedServerVocabConstructsBox.get(key);

          if (serverRaw != null) {
            server = ConstructUses.fromJson(
              Map<String, dynamic>.from(serverRaw),
            );
          }

          final localRaw = await _aggregatedLocalVocabConstructsBox.get(key);

          if (localRaw != null) {
            local = ConstructUses.fromJson(
              Map<String, dynamic>.from(localRaw),
            );
          }
        } else {
          final serverRaw = await _aggregatedServerMorphConstructsBox.get(key);

          if (serverRaw != null) {
            server = ConstructUses.fromJson(
              Map<String, dynamic>.from(serverRaw),
            );
          }

          final localRaw = await _aggregatedLocalMorphConstructsBox.get(key);

          if (localRaw != null) {
            local = ConstructUses.fromJson(
              Map<String, dynamic>.from(localRaw),
            );
          }
        }

        if (server != null) construct.merge(server);
        if (local != null) construct.merge(local);
      }
    });
    return construct;
  }

  Future<Map<ConstructIdentifier, ConstructUses>> getConstructUses(
    Map<ConstructIdentifier, List<ConstructIdentifier>> ids,
  ) async {
    final Map<ConstructIdentifier, ConstructUses> results = {};
    await _transaction(() async {
      for (final entry in ids.entries) {
        final construct = await getConstructUse(entry.value);
        results[entry.key] = construct;
      }
    });
    return results;
  }

  Future<void> clearLocalConstructData() async {
    await _transaction(() async {
      await _localConstructsBox.clear();
      await _aggregatedLocalVocabConstructsBox.clear();
      await _aggregatedLocalMorphConstructsBox.clear();
      await _derivedLocalStatsBox.clear();
    });
  }

  /// Group uses by aggregate key
  Map<String, List<OneConstructUse>> _groupUses(
    List<OneConstructUse> uses,
  ) {
    final Map<String, List<OneConstructUse>> grouped = {};
    for (final u in uses) {
      final key = u.identifier.storageKey;
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

      final List<OneConstructUse> aggregatedVocabUses = [];
      final List<OneConstructUse> aggregatedMorphUses = [];
      final Map<String, List<OneConstructUse>> pendingWrites = {};

      for (final event in events) {
        final ts = event.event.originServerTs;
        final key = TupleKey(
          event.event.eventId,
          ts.toIso8601String(),
        ).toString();

        if (lastUpdated != null && ts.isBefore(lastUpdated)) continue;
        if (existingKeys.contains(key)) continue;

        if (ts.isAfter(mostRecent)) mostRecent = ts;

        pendingWrites[key] = event.content.uses;
        for (final u in event.content.uses) {
          u.constructType == ConstructTypeEnum.vocab
              ? aggregatedVocabUses.add(u)
              : aggregatedMorphUses.add(u);
        }
      }

      if (pendingWrites.isEmpty) return;

      // Write events sequentially
      for (final e in pendingWrites.entries) {
        _serverConstructsBox.put(
          e.key,
          e.value.map((u) => u.toJson()).toList(),
        );
      }

      // Update aggregates
      final aggVocabUpdates = await _aggregateFromBox(
        _aggregatedServerVocabConstructsBox,
        _groupUses(aggregatedVocabUses),
      );

      for (final entry in aggVocabUpdates.entries) {
        await _aggregatedServerVocabConstructsBox.put(
          entry.key,
          entry.value.toJson(),
        );
      }

      final aggMorphUpdates = await _aggregateFromBox(
        _aggregatedServerMorphConstructsBox,
        _groupUses(aggregatedMorphUses),
      );

      for (final entry in aggMorphUpdates.entries) {
        await _aggregatedServerMorphConstructsBox.put(
          entry.key,
          entry.value.toJson(),
        );
      }

      // Update derived stats
      final updatedDerivedStats = derivedData.update(
        [
          ...aggregatedVocabUses,
          ...aggregatedMorphUses,
        ],
      );

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

      final List<OneConstructUse> vocabUses = [];
      final List<OneConstructUse> morphUses = [];
      for (final u in uses) {
        u.constructType == ConstructTypeEnum.vocab
            ? vocabUses.add(u)
            : morphUses.add(u);
      }

      // Update aggregates
      final aggVocabUpdates = await _aggregateFromBox(
        _aggregatedLocalVocabConstructsBox,
        _groupUses(vocabUses),
      );

      for (final entry in aggVocabUpdates.entries) {
        await _aggregatedLocalVocabConstructsBox.put(
          entry.key,
          entry.value.toJson(),
        );
      }

      final aggMorphUpdates = await _aggregateFromBox(
        _aggregatedLocalMorphConstructsBox,
        _groupUses(morphUses),
      );

      for (final entry in aggMorphUpdates.entries) {
        await _aggregatedLocalMorphConstructsBox.put(
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

  Future<List<ConstructUses>> getAggregatedConstructs(
    ConstructTypeEnum type,
  ) async {
    Map<String, ConstructUses> combined = {};
    final stopwatch = Stopwatch()..start();
    await _transaction(() async {
      final localKeys = await switch (type) {
        ConstructTypeEnum.vocab =>
          _aggregatedLocalVocabConstructsBox.getAllKeys(),
        ConstructTypeEnum.morph =>
          _aggregatedLocalMorphConstructsBox.getAllKeys()
      };

      final serverKeys = await switch (type) {
        ConstructTypeEnum.vocab =>
          _aggregatedServerVocabConstructsBox.getAllKeys(),
        ConstructTypeEnum.morph =>
          _aggregatedServerMorphConstructsBox.getAllKeys()
      };

      final serverValues = await switch (type) {
        ConstructTypeEnum.vocab =>
          _aggregatedServerVocabConstructsBox.getAll(serverKeys),
        ConstructTypeEnum.morph =>
          _aggregatedServerMorphConstructsBox.getAll(serverKeys)
      };

      final serverConstructs = serverValues
          .map((e) => ConstructUses.fromJson(Map<String, dynamic>.from(e!)))
          .toList();

      final serverAgg = Map.fromIterables(
        serverKeys,
        serverConstructs,
      );

      if (localKeys.isEmpty) {
        combined = serverAgg;
        return;
      }

      final localValues = await switch (type) {
        ConstructTypeEnum.vocab =>
          _aggregatedLocalVocabConstructsBox.getAll(localKeys),
        ConstructTypeEnum.morph =>
          _aggregatedLocalMorphConstructsBox.getAll(localKeys)
      };

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
          serverModel.merge(localModel);
          combined[key] = serverModel;
        } else {
          combined[key] = localModel;
        }
      }
    });

    stopwatch.stop();
    Logs().i(
      "Combining aggregates took ${stopwatch.elapsedMilliseconds} ms",
    );

    return combined.values.toList();
  }
}
