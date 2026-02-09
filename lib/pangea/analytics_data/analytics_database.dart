// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:async';
import 'dart:math';

import 'package:matrix/matrix.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:synchronized/synchronized.dart';

import 'package:fluffychat/pangea/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
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
  late Box<Map> _derivedStatsBox;

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

  static const String _derivedStatsBoxName = 'box_derived_stats';

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

  final _lock = Lock();

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
        _derivedStatsBoxName,
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
    _derivedStatsBox = _collection.openBox<Map>(
      _derivedStatsBoxName,
    );
  }

  Future<void> delete() async {
    await _collection.deleteDatabase(
      database?.path ?? name,
      sqfliteFactory ?? idbFactory,
    );
  }

  Future<void> clear() async {
    _lastEventTimestampBox.clearQuickAccessCache();
    _serverConstructsBox.clearQuickAccessCache();
    _localConstructsBox.clearQuickAccessCache();
    _aggregatedServerVocabConstructsBox.clearQuickAccessCache();
    _aggregatedLocalVocabConstructsBox.clearQuickAccessCache();
    _aggregatedServerMorphConstructsBox.clearQuickAccessCache();
    _aggregatedLocalMorphConstructsBox.clearQuickAccessCache();
    _derivedStatsBox.clearQuickAccessCache();
    await _collection.clear();
  }

  Future<T> _transaction<T>(Future<T> Function() action) {
    return _lock.synchronized(action);
  }

  Box<Map> _aggBox(ConstructTypeEnum type, bool local) =>
      switch ((type, local)) {
        (ConstructTypeEnum.vocab, true) => _aggregatedLocalVocabConstructsBox,
        (ConstructTypeEnum.vocab, false) => _aggregatedServerVocabConstructsBox,
        (ConstructTypeEnum.morph, true) => _aggregatedLocalMorphConstructsBox,
        (ConstructTypeEnum.morph, false) => _aggregatedServerMorphConstructsBox,
      };

  Future<String?> getUserID() => _lastEventTimestampBox.get('user_id');

  Future<DateTime?> getLastUpdated() async {
    final entry = await _lastEventTimestampBox.get('last_updated');
    if (entry == null) return null;
    return DateTime.tryParse(entry);
  }

  Future<DateTime?> getLastEventTimestamp() async {
    final timestampString =
        await _lastEventTimestampBox.get('last_event_timestamp');
    if (timestampString == null) return null;
    return DateTime.parse(timestampString);
  }

  Future<DerivedAnalyticsDataModel> getDerivedStats() async {
    final raw = await _derivedStatsBox.get('derived_stats');
    return raw == null
        ? DerivedAnalyticsDataModel()
        : DerivedAnalyticsDataModel.fromJson(
            Map<String, dynamic>.from(raw),
          );
  }

  Future<List<OneConstructUse>> getUses({
    int? count,
    String? roomId,
    DateTime? since,
    List<ConstructUseTypeEnum>? types,
  }) async {
    final stopwatch = Stopwatch()..start();
    final results = <OneConstructUse>[];

    bool addUseIfValid(OneConstructUse use) {
      if (since != null && use.timeStamp.isBefore(since)) {
        return false; // stop iteration entirely
      }
      if (roomId != null && use.metadata.roomId != roomId) {
        return true; // skip but continue
      }
      if (types != null && !types.contains(use.useType)) {
        return true; // skip but continue
      }

      results.add(use);
      return count == null || results.length < count;
    }

    // ---- Local uses ----
    final localUses = await getLocalUses()
      ..sort((a, b) => b.timeStamp.compareTo(a.timeStamp));

    for (final use in localUses) {
      if (!addUseIfValid(use)) break;
    }

    if (count != null && results.length >= count) {
      stopwatch.stop();
      Logs().i("Get uses took ${stopwatch.elapsedMilliseconds} ms");
      return results;
    }

    // ---- Server uses ----
    final serverKeys = await _serverConstructsBox.getAllKeys()
      ..sort(
        (a, b) =>
            int.parse(b.split('|')[1]).compareTo(int.parse(a.split('|')[1])),
      );

    for (final key in serverKeys) {
      final serverUses = await getServerUses(key)
        ..sort((a, b) => b.timeStamp.compareTo(a.timeStamp));

      for (final use in serverUses) {
        if (!addUseIfValid(use)) break;
      }

      if (count != null && results.length >= count) break;
    }

    stopwatch.stop();
    Logs().i("Get uses took ${stopwatch.elapsedMilliseconds} ms");
    return results;
  }

  Future<List<OneConstructUse>> getLocalUses() async {
    final List<OneConstructUse> uses = [];
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
    return uses;
  }

  Future<List<OneConstructUse>> getServerUses(String key) async {
    final List<OneConstructUse> uses = [];
    final serverValues = await _serverConstructsBox.get(key);
    if (serverValues == null) return [];

    for (final entry in serverValues) {
      uses.add(
        OneConstructUse.fromJson(
          Map<String, dynamic>.from(entry),
        ),
      );
    }
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
    assert(ids.isNotEmpty);

    final ConstructUses construct = ConstructUses(
      uses: [],
      constructType: ids.first.type,
      lemma: ids.first.lemma,
      category: ids.first.category,
    );

    for (final id in ids) {
      final key = id.storageKey;

      ConstructUses? server;
      ConstructUses? local;

      final serverBox = _aggBox(id.type, false);
      final localBox = _aggBox(id.type, true);

      final serverRaw = await serverBox.get(key);
      if (serverRaw != null) {
        server = ConstructUses.fromJson(
          Map<String, dynamic>.from(serverRaw),
        );
      }

      final localRaw = await localBox.get(key);
      if (localRaw != null) {
        local = ConstructUses.fromJson(
          Map<String, dynamic>.from(localRaw),
        );
      }

      if (server != null) construct.merge(server);
      if (local != null) construct.merge(local);
    }
    return construct;
  }

  Future<Map<ConstructIdentifier, ConstructUses>> getConstructUses(
    Map<ConstructIdentifier, List<ConstructIdentifier>> ids,
  ) async {
    final Map<ConstructIdentifier, ConstructUses> results = {};
    for (final entry in ids.entries) {
      final construct = await getConstructUse(entry.value);
      results[entry.key] = construct;
    }
    return results;
  }

  Future<void> clearLocalConstructData() async {
    await _transaction(() async {
      await _localConstructsBox.clear();
      await _aggregatedLocalVocabConstructsBox.clear();
      await _aggregatedLocalMorphConstructsBox.clear();
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

      if (raw != null) {
        model = ConstructUses.fromJson(Map<String, dynamic>.from(raw));
      } else {
        final u = usesForKey.first;
        model = ConstructUses(
          uses: [],
          constructType: u.constructType,
          lemma: u.lemma,
          category: u.category,
        );
      }

      model.addUses(usesForKey);
      updates[key] = model;
    }

    return updates;
  }

  Future<Map<String, ConstructUses>> _aggregateFromBox(
    Box<Map> box,
    Map<String, List<OneConstructUse>> grouped,
  ) async {
    final keys = grouped.keys.toList();
    final existing = await box.getAll(keys);

    final existingMap = Map.fromIterables(keys, existing);
    return _aggregateConstructs(grouped, existingMap);
  }

  Future<List<ConstructUses>> getAggregatedConstructs(
    ConstructTypeEnum type,
  ) async {
    Map<String, ConstructUses> combined = {};
    final stopwatch = Stopwatch()..start();

    final localKeys = await _aggBox(type, true).getAllKeys();
    final serverKeys = await _aggBox(type, false).getAllKeys();

    final serverValues = await _aggBox(type, false).getAll(serverKeys);
    final serverConstructs = serverValues
        .map((e) => ConstructUses.fromJson(Map<String, dynamic>.from(e!)))
        .toList();

    final serverAgg = Map.fromIterables(
      serverKeys,
      serverConstructs,
    );

    if (localKeys.isEmpty) {
      combined = serverAgg;
    } else {
      final localValues = await _aggBox(type, true).getAll(localKeys);
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
    }

    stopwatch.stop();
    Logs().i(
      "Combining aggregates took ${stopwatch.elapsedMilliseconds} ms",
    );

    return combined.values.toList();
  }

  Future<void> updateUserID(String userID) {
    return _transaction(() async {
      await _lastEventTimestampBox.put(
        'user_id',
        userID,
      );
    });
  }

  Future<void> updateLastUpdated(DateTime timestamp) {
    return _transaction(() async {
      await _lastEventTimestampBox.put(
        'last_updated',
        timestamp.toIso8601String(),
      );
    });
  }

  Future<void> updateXPOffset(int offset) {
    return _transaction(() async {
      final stats = await getDerivedStats();
      final updatedStats = stats.copyWith(offset: offset);
      await _derivedStatsBox.put(
        'derived_stats',
        updatedStats.toJson(),
      );
    });
  }

  Future<void> updateDerivedStats(DerivedAnalyticsDataModel newStats) =>
      _derivedStatsBox.put(
        'derived_stats',
        newStats.toJson(),
      );

  Future<void> updateServerAnalytics(
    List<ConstructAnalyticsEvent> events,
  ) async {
    if (events.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    await _transaction(() async {
      final lastUpdated = await getLastEventTimestamp();

      DateTime mostRecent = lastUpdated ?? events.first.event.originServerTs;
      final existingKeys = (await _serverConstructsBox.getAllKeys()).toSet();

      final List<OneConstructUse> aggregatedVocabUses = [];
      final List<OneConstructUse> aggregatedMorphUses = [];
      final Map<String, List<OneConstructUse>> pendingWrites = {};

      for (final event in events) {
        final ts = event.event.originServerTs;
        final key = TupleKey(
          event.event.eventId,
          ts.millisecondsSinceEpoch.toString(),
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

      // Update timestamp
      await _lastEventTimestampBox.put(
        'last_event_timestamp',
        mostRecent.toIso8601String(),
      );
    });

    await updateLastUpdated(DateTime.now());

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
      final key = DateTime.now().millisecondsSinceEpoch;
      _localConstructsBox.put(
        key.toString(),
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

    await updateLastUpdated(DateTime.now());

    stopwatch.stop();
    Logs().i("Local analytics update took ${stopwatch.elapsedMilliseconds} ms");
  }
}
