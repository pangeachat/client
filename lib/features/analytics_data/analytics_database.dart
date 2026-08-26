// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:synchronized/synchronized.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_event.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';

import 'package:matrix/src/database/database_file_storage_stub.dart'
    if (dart.library.io) 'package:matrix/src/database/database_file_storage_io.dart';
import 'package:matrix/src/database/indexeddb_box.dart'
    if (dart.library.io) 'package:matrix/src/database/sqflite_box.dart';

/// Thrown when a caller reaches [AnalyticsDatabase] after its store has been
/// closed or deleted. The store cannot be revived in place — the owning
/// service has to build a new [AnalyticsDatabase] — so a caller that catches
/// this should stop retrying rather than back off and try the same instance
/// again.
class AnalyticsDatabaseClosedException implements Exception {
  final String databaseName;

  const AnalyticsDatabaseClosedException(this.databaseName);

  @override
  String toString() =>
      'AnalyticsDatabaseClosedException: analytics store "$databaseName" is '
      'closed; the owning service must reinitialize before it can be used';
}

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

  bool _isClosed = false;

  /// Whether this instance's store has been closed or deleted.
  ///
  /// Every box operation runs against a single cached connection — on web,
  /// one `IDBDatabase` held by the SDK's `BoxCollection`. Once that connection
  /// closes there is no per-call recovery: every subsequent operation throws.
  /// Callers read this instead of discovering it one exception at a time.
  ///
  /// Set both by [delete] (a close we initiate) and by [_transaction] when it
  /// sees a closed-store failure (a close initiated elsewhere — see
  /// [_isClosedStoreError]).
  bool get isClosed => _isClosed;

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
    _serverConstructsBox = _collection.openBox<List>(_serverConstructsBoxName);
    _localConstructsBox = _collection.openBox<List>(_localConstructsBoxName);
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
    _derivedStatsBox = _collection.openBox<Map>(_derivedStatsBoxName);
  }

  Future<void> delete() async {
    // Latched BEFORE the await, not after: `deleteDatabase` closes the
    // connection as its first step, so anything that reaches a box during the
    // delete is already doomed. Marking it up front turns that window into an
    // AnalyticsDatabaseClosedException instead of a raw store error.
    _isClosed = true;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'AnalyticsDatabase.delete: closing analytics store',
        data: {'database': name},
      ),
    );
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

  /// Drop the boxes' in-memory decoded-value caches without touching stored
  /// data, so a benchmark can measure cold (storage-backed) reads.
  @visibleForTesting
  void clearQuickAccessCaches() {
    _lastEventTimestampBox.clearQuickAccessCache();
    _serverConstructsBox.clearQuickAccessCache();
    _localConstructsBox.clearQuickAccessCache();
    _aggregatedServerVocabConstructsBox.clearQuickAccessCache();
    _aggregatedLocalVocabConstructsBox.clearQuickAccessCache();
    _aggregatedServerMorphConstructsBox.clearQuickAccessCache();
    _aggregatedLocalMorphConstructsBox.clearQuickAccessCache();
    _derivedStatsBox.clearQuickAccessCache();
  }

  /// A closed store fails the same way for every caller, so the check and the
  /// latch live here rather than at each call site.
  Future<T> _transaction<T>(Future<T> Function() action) async {
    if (_isClosed) throw AnalyticsDatabaseClosedException(name);

    try {
      return await _lock.synchronized(action);
    } catch (e) {
      if (!_isClosedStoreError(e)) rethrow;

      // A close we did not initiate — the store was still live as far as this
      // instance knew. Latch it so the next caller fails fast instead of
      // issuing another doomed request, and leave a breadcrumb recording that
      // this instance learned about the close from a failure rather than from
      // delete().
      _isClosed = true;
      Sentry.addBreadcrumb(
        Breadcrumb(
          message:
              'AnalyticsDatabase: store closed externally; latched as closed',
          data: {'database': name, 'error': e.toString()},
          level: SentryLevel.warning,
        ),
      );
      throw AnalyticsDatabaseClosedException(name);
    }
  }

  /// Whether [e] is the store reporting that its connection is gone.
  ///
  /// Matched on the message rather than the type: on web this originates as a
  /// JS `DOMException` crossing the dart2js boundary, so there is no Dart type
  /// to catch. The strings are the browser's own and are stable across
  /// engines — `InvalidStateError` is the DOM name for operating on a closed
  /// or closing `IDBDatabase`, and sqflite's equivalent says the database is
  /// closed. Anything else is a real failure and must keep propagating.
  static bool _isClosedStoreError(Object e) {
    final message = e.toString();
    return message.contains('InvalidStateError') ||
        message.contains('database_closed') ||
        message.contains('DatabaseException(database is closed)');
  }

  Box<Map> _aggBox(ConstructTypeEnum type, bool local) =>
      switch ((type, local)) {
        (ConstructTypeEnum.vocab, true) => _aggregatedLocalVocabConstructsBox,
        (ConstructTypeEnum.vocab, false) => _aggregatedServerVocabConstructsBox,
        (ConstructTypeEnum.morph, true) => _aggregatedLocalMorphConstructsBox,
        (ConstructTypeEnum.morph, false) => _aggregatedServerMorphConstructsBox,
      };

  String _langKey(String key, String language) => '$language|$key';

  bool _isLanguageKey(String key, String language) =>
      key.startsWith('$language|');

  Future<String?> getUserID() => _lastEventTimestampBox.get(ModelKey.userId);

  Future<DateTime?> getLastUpdated(String language) async {
    final entry = await _lastEventTimestampBox.get(
      _langKey('last_updated', language),
    );
    if (entry == null) return null;
    return DateTime.tryParse(entry);
  }

  Future<DateTime?> getLastEventTimestamp(String language) async {
    final timestampString = await _lastEventTimestampBox.get(
      _langKey('last_event_timestamp', language),
    );
    if (timestampString == null) return null;
    return DateTime.parse(timestampString);
  }

  Future<String?> getCurrentLanguage() async {
    return _lastEventTimestampBox.get('current_language');
  }

  Future<String?> getAnalyticsRoomId() async {
    return _lastEventTimestampBox.get('analytics_room_id');
  }

  Future<DerivedAnalyticsDataModel> getDerivedStats(String language) async {
    final raw = await _derivedStatsBox.get(_langKey('derived_stats', language));
    return raw == null
        ? DerivedAnalyticsDataModel()
        : DerivedAnalyticsDataModel.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Server event keys are `lang|eventId|originServerTs`. When [since] is
  /// set, keys whose event is older than `since - _sinceSkewAllowance` are
  /// skipped before any read: a use is uploaded after it happens, so its
  /// event's server timestamp is at or after the use's client timestamp
  /// unless the client clock ran ahead of the server. The allowance keeps
  /// that case correct for any plausible skew (#8420).
  static const Duration _sinceSkewAllowance = Duration(days: 1);

  /// How many server event keys are read per `getAll` while walking history
  /// newest-first for [getUses]; small enough that a `count`-limited read
  /// stops early, large enough to amortise the box round-trip.
  static const int _serverKeyChunk = 64;

  Future<List<OneConstructUse>> getUses(
    String language, {
    int? count,
    String? roomId,
    DateTime? since,
    List<ConstructUseTypeEnum>? types,
  }) async {
    final stopwatch = Stopwatch()..start();
    final results = <OneConstructUse>[];

    /// Returns false when iteration of the current (desc-sorted) list should
    /// stop: either everything remaining is older than [since], or [count]
    /// has been reached.
    bool addUse(OneConstructUse use) {
      if (since != null && use.timeStamp.isBefore(since)) return false;
      results.add(use);
      return count == null || results.length < count;
    }

    bool countReached() => count != null && results.length >= count;

    // ---- Local uses ----
    final localUses =
        await _readLocalUses(language, roomId: roomId, types: types)
          ..sort((a, b) => b.timeStamp.compareTo(a.timeStamp));

    for (final use in localUses) {
      if (!addUse(use)) break;
    }

    if (countReached()) {
      stopwatch.stop();
      Logs().i("Get uses took ${stopwatch.elapsedMilliseconds} ms");
      return results;
    }

    // ---- Server uses ----
    final sinceCutoff = since?.subtract(_sinceSkewAllowance);
    final serverKeys = (await _serverConstructsBox.getAllKeys())
        .where((key) => _isLanguageKey(key, language))
        .map((key) {
          final parts = key.split('|');
          // Filter out malformed or legacy keys that don't have a timestamp
          final ts = parts.length >= 3 ? int.tryParse(parts[2]) : null;
          return ts == null ? null : (key: key, ts: ts);
        })
        .nonNulls
        .where(
          (e) =>
              sinceCutoff == null || e.ts >= sinceCutoff.millisecondsSinceEpoch,
        )
        .sorted((a, b) => b.ts.compareTo(a.ts))
        .map((e) => e.key)
        .toList();

    for (
      var i = 0;
      i < serverKeys.length && !countReached();
      i += _serverKeyChunk
    ) {
      final chunk = serverKeys.sublist(
        i,
        min(i + _serverKeyChunk, serverKeys.length),
      );
      final values = await _serverConstructsBox.getAll(chunk);

      for (final raw in values) {
        final serverUses = _parseUses(raw, roomId: roomId, types: types)
          ..sort((a, b) => b.timeStamp.compareTo(a.timeStamp));

        for (final use in serverUses) {
          if (!addUse(use)) break;
        }

        if (countReached()) break;
      }
    }

    stopwatch.stop();
    Logs().i("Get uses took ${stopwatch.elapsedMilliseconds} ms");
    return results;
  }

  Future<List<OneConstructUse>> getLocalUses(String language) =>
      _readLocalUses(language);

  Future<List<OneConstructUse>> _readLocalUses(
    String language, {
    String? roomId,
    List<ConstructUseTypeEnum>? types,
  }) async {
    final List<OneConstructUse> uses = [];
    final localKeys = (await _localConstructsBox.getAllKeys())
        .where((key) => _isLanguageKey(key, language))
        .toList();
    if (localKeys.isEmpty) return uses;

    final localValues = await _localConstructsBox.getAll(localKeys);
    for (final rawList in localValues) {
      uses.addAll(_parseUses(rawList, roomId: roomId, types: types));
    }
    return uses;
  }

  Future<List<OneConstructUse>> getServerUses(String key) async =>
      _parseUses(await _serverConstructsBox.get(key));

  /// Deserialize a stored uses list, applying the [roomId] / [types] filters
  /// on the raw JSON first so non-matching uses are never constructed. The
  /// raw fields mirror [OneConstructUse.toJson] (`chatId`, `useType`).
  static List<OneConstructUse> _parseUses(
    List? rawList, {
    String? roomId,
    List<ConstructUseTypeEnum>? types,
  }) {
    if (rawList == null) return const [];
    final List<OneConstructUse> uses = [];
    for (final raw in rawList) {
      if (roomId != null && raw['chatId'] != roomId) continue;
      if (types != null &&
          !types.contains(
            ConstructUseTypeEnum.fromString(raw['useType'] as String? ?? ''),
          )) {
        continue;
      }
      uses.add(OneConstructUse.fromJson(Map<String, dynamic>.from(raw)));
    }
    return uses;
  }

  Future<int> getLocalConstructCount(String language) async {
    final keys = (await _localConstructsBox.getAllKeys()).where(
      (key) => _isLanguageKey(key, language),
    );
    return keys.length;
  }

  Future<ConstructUses> getConstructUse(
    List<ConstructIdentifier> ids,
    String language,
  ) async {
    assert(ids.isNotEmpty);
    final result = await getConstructUses({ids.first: ids}, language);
    return result[ids.first]!;
  }

  /// One [ConstructUses] per key of [ids], each merged from the server and
  /// local aggregates of every id in its group (server then local, in group
  /// order). All rows are fetched with one `getAll` per box (#8420).
  Future<Map<ConstructIdentifier, ConstructUses>> getConstructUses(
    Map<ConstructIdentifier, List<ConstructIdentifier>> ids,
    String language,
  ) async {
    // Collect the storage keys needed from each of the four aggregate boxes.
    final wanted = <Box<Map>, Set<String>>{};
    for (final group in ids.values) {
      for (final id in group) {
        final key = _langKey(id.storageKey, language);
        (wanted[_aggBox(id.type, false)] ??= {}).add(key);
        (wanted[_aggBox(id.type, true)] ??= {}).add(key);
      }
    }

    final fetched = <Box<Map>, Map<String, Map?>>{};
    await Future.wait(
      wanted.entries.map((e) async {
        final keys = e.value.toList();
        final values = await e.key.getAll(keys);
        fetched[e.key] = Map.fromIterables(keys, values);
      }),
    );

    final Map<ConstructIdentifier, ConstructUses> results = {};
    for (final entry in ids.entries) {
      final group = entry.value;
      // An empty group (id excluded by the merge table) yields an empty
      // construct for the requested id, as the per-id path always did.
      final head = group.isEmpty ? entry.key : group.first;
      final construct = ConstructUses(
        uses: [],
        constructType: head.type,
        lemma: head.lemma,
        category: head.category,
      );

      for (final id in group) {
        final key = _langKey(id.storageKey, language);
        final serverRaw = fetched[_aggBox(id.type, false)]?[key];
        final localRaw = fetched[_aggBox(id.type, true)]?[key];
        if (serverRaw != null) {
          construct.merge(
            ConstructUses.fromJson(Map<String, dynamic>.from(serverRaw)),
          );
        }
        if (localRaw != null) {
          construct.merge(
            ConstructUses.fromJson(Map<String, dynamic>.from(localRaw)),
          );
        }
      }
      results[entry.key] = construct;
    }
    return results;
  }

  Future<void> clearLocalConstructData(String language) async {
    await _transaction(() async {
      final localKeys = (await _localConstructsBox.getAllKeys())
          .where((key) => _isLanguageKey(key, language))
          .toList();

      final localVocabAggKeys =
          (await _aggregatedLocalVocabConstructsBox.getAllKeys())
              .where((key) => _isLanguageKey(key, language))
              .toList();

      final localMorphAggKeys =
          (await _aggregatedLocalMorphConstructsBox.getAllKeys())
              .where((key) => _isLanguageKey(key, language))
              .toList();

      await _localConstructsBox.deleteAll(localKeys);
      await _aggregatedLocalVocabConstructsBox.deleteAll(localVocabAggKeys);
      await _aggregatedLocalMorphConstructsBox.deleteAll(localMorphAggKeys);
    });
  }

  /// Group uses by aggregate key
  Map<String, List<OneConstructUse>> _groupUses(
    List<OneConstructUse> uses,
    String language,
  ) {
    final Map<String, List<OneConstructUse>> grouped = {};
    for (final u in uses) {
      final key = _langKey(u.identifier.storageKey, language);
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

  /// The uncapped xp sum of every stored aggregate of [type] for [language] —
  /// one entry per storage row (server and local rows for the same construct
  /// are returned separately; callers add them), each tagged with the row's
  /// [ConstructIdentifier].
  ///
  /// This is the cheap read behind the total-XP recompute (#8418): it walks the
  /// raw aggregate JSON and sums `xp` per use, without constructing a
  /// [OneConstructUse] (no DateTime parsing, no enum lookups beyond the
  /// legacy `xp`-less fallback). It must stay equivalent to
  /// `getAggregatedConstructs(...).fold((c) => c.uses.fold(xp))` — see the
  /// differential test in `analytics_database_test.dart`.
  Future<List<({ConstructIdentifier id, int xp})>> getAggregateXPSums(
    ConstructTypeEnum type,
    String language,
  ) async {
    final results = <({ConstructIdentifier id, int xp})>[];

    Future<void> read(Box<Map> box) async {
      final keys = (await box.getAllKeys())
          .where((key) => _isLanguageKey(key, language))
          .toList();
      if (keys.isEmpty) return;
      final values = await box.getAll(keys);
      for (final raw in values) {
        if (raw == null) continue;
        final id = ConstructIdentifier.fromJson(
          Map<String, dynamic>.from(raw['construct_id']),
        );
        results.add((id: id, xp: _rawUsesXP(raw['uses'])));
      }
    }

    await Future.wait([read(_aggBox(type, false)), read(_aggBox(type, true))]);
    return results;
  }

  /// The identifier of every stored aggregate of [type] for [language] that
  /// has at least one use — server rows first in box order, then local-only
  /// rows — with server and local rows for the same construct collapsed to
  /// one entry, exactly the order and membership `getAggregatedConstructs`
  /// yields (its rows with an empty use list contribute nothing downstream).
  ///
  /// This is what the merge table needs at init: it only ever consumed the
  /// identifier of each use, and every use in a row carries the row's
  /// identifier, so the uses themselves are never deserialized here.
  Future<List<ConstructIdentifier>> getAggregateIds(
    ConstructTypeEnum type,
    String language,
  ) async {
    // key → id when the row has uses, null placeholder to hold the server
    // row's position when only its local counterpart has uses.
    final byKey = <String, ConstructIdentifier?>{};

    Future<void> read(Box<Map> box, {required bool server}) async {
      final keys = (await box.getAllKeys())
          .where((key) => _isLanguageKey(key, language))
          .toList();
      if (keys.isEmpty) return;
      final values = await box.getAll(keys);
      for (var i = 0; i < keys.length; i++) {
        final raw = values[i];
        if (raw == null) continue;
        final key = keys[i];
        final uses = raw['uses'];
        final hasUses = uses is List && uses.isNotEmpty;
        if (server) {
          byKey[key] = hasUses
              ? ConstructIdentifier.fromJson(
                  Map<String, dynamic>.from(raw['construct_id']),
                )
              : null;
        } else if (hasUses && byKey[key] == null) {
          // Either a local-only row (appended) or a server row without uses
          // (position kept — LinkedHashMap keeps insertion order on update).
          byKey[key] = ConstructIdentifier.fromJson(
            Map<String, dynamic>.from(raw['construct_id']),
          );
        }
      }
    }

    // Server first so its rows come first; local must see server's placeholders.
    await read(_aggBox(type, false), server: true);
    await read(_aggBox(type, true), server: false);
    return byKey.values.nonNulls.toList();
  }

  /// Sum of `xp` over a raw `uses` JSON list, mirroring
  /// [OneConstructUse.fromJson]'s `xp ?? useType.pointValue` fallback.
  static int _rawUsesXP(dynamic uses) {
    if (uses is! List) return 0;
    var total = 0;
    for (final u in uses) {
      if (u is! Map) continue;
      final xp = u['xp'];
      if (xp is int) {
        total += xp;
      } else if (xp is num) {
        total += xp.toInt();
      } else {
        total += ConstructUseTypeEnum.fromString(u['useType']).pointValue;
      }
    }
    return total;
  }

  Future<List<ConstructUses>> getAggregatedConstructs(
    ConstructTypeEnum type,
    String language,
  ) async {
    Map<String, ConstructUses> combined = {};
    final stopwatch = Stopwatch()..start();

    final localKeys = (await _aggBox(
      type,
      true,
    ).getAllKeys()).where((key) => _isLanguageKey(key, language)).toList();
    final serverKeys = (await _aggBox(
      type,
      false,
    ).getAllKeys()).where((key) => _isLanguageKey(key, language)).toList();

    final serverValues = await _aggBox(type, false).getAll(serverKeys);
    final serverConstructs = serverValues
        .map((e) => ConstructUses.fromJson(Map<String, dynamic>.from(e!)))
        .toList();

    final serverAgg = Map.fromIterables(serverKeys, serverConstructs);

    if (localKeys.isEmpty) {
      combined = serverAgg;
    } else {
      final localValues = await _aggBox(type, true).getAll(localKeys);
      final localConstructs = localValues
          .map((e) => ConstructUses.fromJson(Map<String, dynamic>.from(e!)))
          .toList();

      final localAgg = Map.fromIterables(localKeys, localConstructs);

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
    Logs().i("Combining aggregates took ${stopwatch.elapsedMilliseconds} ms");

    return combined.values.toList();
  }

  Future<void> updateUserID(String userID) {
    return _transaction(() async {
      await _lastEventTimestampBox.put(ModelKey.userId, userID);
    });
  }

  Future<void> updateCurrentLanguage(String language) {
    return _transaction(() async {
      await _lastEventTimestampBox.put('current_language', language);
    });
  }

  Future<void> updateAnalyticsRoomId(String roomId) {
    return _transaction(() async {
      await _lastEventTimestampBox.put('analytics_room_id', roomId);
    });
  }

  Future<void> _updateLastUpdated(DateTime timestamp, String language) async {
    return _transaction(() async {
      await _lastEventTimestampBox.put(
        _langKey('last_updated', language),
        timestamp.toIso8601String(),
      );
    });
  }

  Future<void> updateXPOffset(int offset, String language) async {
    return _transaction(() async {
      final stats = await getDerivedStats(language);
      final updatedStats = stats.copyWithOffset(offset);
      await _derivedStatsBox.put(
        _langKey('derived_stats', language),
        updatedStats.toJson(),
      );
    });
  }

  Future<void> updateTotalXP(int totalXP, String language) {
    return _transaction(() async {
      final stats = await getDerivedStats(language);
      final updatedStats = stats.copyWithTotalXP(totalXP);
      await _derivedStatsBox.put(
        _langKey('derived_stats', language),
        updatedStats.toJson(),
      );
    });
  }

  Future<void> updateDerivedStats(
    DerivedAnalyticsDataModel newStats,
    String language,
  ) => _derivedStatsBox.put(
    _langKey('derived_stats', language),
    newStats.toJson(),
  );

  Future<void> updateServerAnalytics(
    List<ConstructAnalyticsEvent> events,
    String language,
  ) async {
    if (events.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    await _transaction(() async {
      final lastUpdated = await getLastEventTimestamp(language);

      DateTime mostRecent = lastUpdated ?? events.first.event.originServerTs;
      final existingEventIds = (await _serverConstructsBox.getAllKeys())
          .where((key) => _isLanguageKey(key, language))
          .map((key) => key.split('|'))
          .where((parts) => parts.length >= 3)
          .map((parts) => parts[1])
          .toSet();

      final List<OneConstructUse> aggregatedVocabUses = [];
      final List<OneConstructUse> aggregatedMorphUses = [];
      final Map<String, List<OneConstructUse>> pendingWrites = {};

      for (final event in events) {
        if (existingEventIds.contains(event.event.eventId)) continue;
        final ts = event.event.originServerTs;
        final key = TupleKey(
          event.event.eventId,
          ts.millisecondsSinceEpoch.toString(),
        ).toString();

        final serverEventKey = _langKey(key, language);
        if (lastUpdated != null && ts.isBefore(lastUpdated)) continue;

        if (ts.isAfter(mostRecent)) mostRecent = ts;

        pendingWrites[serverEventKey] = event.content.uses;
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
        _groupUses(aggregatedVocabUses, language),
      );

      for (final entry in aggVocabUpdates.entries) {
        await _aggregatedServerVocabConstructsBox.put(
          entry.key,
          entry.value.toJson(),
        );
      }

      final aggMorphUpdates = await _aggregateFromBox(
        _aggregatedServerMorphConstructsBox,
        _groupUses(aggregatedMorphUses, language),
      );

      for (final entry in aggMorphUpdates.entries) {
        await _aggregatedServerMorphConstructsBox.put(
          entry.key,
          entry.value.toJson(),
        );
      }

      // Update timestamp
      await _lastEventTimestampBox.put(
        _langKey('last_event_timestamp', language),
        mostRecent.toIso8601String(),
      );
    });

    await _updateLastUpdated(DateTime.now(), language);

    stopwatch.stop();
    Logs().i(
      "Server analytics update took ${stopwatch.elapsedMilliseconds} ms",
    );
  }

  Future<void> updateLocalAnalytics(
    List<OneConstructUse> uses,
    String language,
  ) async {
    if (uses.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    await _transaction(() async {
      // Store local constructs
      final key = DateTime.now().millisecondsSinceEpoch;
      _localConstructsBox.put(
        _langKey(key.toString(), language),
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
        _groupUses(vocabUses, language),
      );

      for (final entry in aggVocabUpdates.entries) {
        await _aggregatedLocalVocabConstructsBox.put(
          entry.key,
          entry.value.toJson(),
        );
      }

      final aggMorphUpdates = await _aggregateFromBox(
        _aggregatedLocalMorphConstructsBox,
        _groupUses(morphUses, language),
      );

      for (final entry in aggMorphUpdates.entries) {
        await _aggregatedLocalMorphConstructsBox.put(
          entry.key,
          entry.value.toJson(),
        );
      }
    });

    await _updateLastUpdated(DateTime.now(), language);

    stopwatch.stop();
    Logs().i("Local analytics update took ${stopwatch.elapsedMilliseconds} ms");
  }
}
