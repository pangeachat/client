import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_event.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_database.dart';
import 'package:fluffychat/features/analytics_data/analytics_database_builder.dart';
import 'package:fluffychat/features/analytics_data/analytics_sync_controller.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_events.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_service.dart';
import 'package:fluffychat/features/analytics_data/blocked_constructs_cache.dart';
import 'package:fluffychat/features/analytics_data/construct_merge_table.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _AnalyticsClient {
  final Client client;
  final AnalyticsDatabase database;

  _AnalyticsClient({required this.client, required this.database});
}

class AnalyticsStreamUpdate {
  final int points;

  /// Uncapped point value of the update's added uses — see
  /// [XPGainedEvent.totalPoints]. Read only by the XP gain/loss animation.
  final int totalPoints;

  final Set<ConstructIdentifier>? blockedConstructs;
  final Set<ConstructIdentifier>? restoredConstructs;

  final String? targetID;

  AnalyticsStreamUpdate({
    this.points = 0,
    this.totalPoints = 0,
    this.blockedConstructs,
    this.restoredConstructs,
    this.targetID,
  });
}

class AnalyticsDataService {
  _AnalyticsClient? _analyticsClient;

  /// The account's client, kept so [accountUserId] can be read from it: this
  /// service may be constructed BEFORE login (userID null then), and the dosage
  /// tracker must key on the SAME mxid the send path uses once logged in.
  final Client _accountClient;

  /// The account (mxid) as the client currently reports it. Read live for
  /// PRE-logout callers (e.g. the pre-logout telemetry flush). It goes null once
  /// the SDK's `logout()` runs `clear()`, which nulls userID BEFORE it emits
  /// `loggedOut` (client.dart) — so the POST-logout teardown must NOT rely on
  /// this: [AnalyticsUpdateService] pins the id at start() and disposes by that
  /// pinned value instead (otherwise disposeAccount would be handed '' and leak
  /// the account's open span + tracker).
  String? get accountUserId => _accountClient.userID;

  /// The account's current bearer, for the best-effort dosage lane. Read live
  /// for the same reason as [accountUserId]: tokens refresh mid-session, and a
  /// snapshot taken at construction would post a heartbeat flush under a stale
  /// one. Null after logout invalidates it, which the buffer treats as "hold,
  /// do not attempt".
  String? get accountAccessToken => _accountClient.accessToken;

  late final AnalyticsUpdateDispatcher updateDispatcher;
  late final AnalyticsUpdateService updateService;
  AnalyticsSyncController? _syncController;
  final ConstructMergeTable _mergeTable = ConstructMergeTable();

  Completer<void> initCompleter = Completer<void>();
  Object? initError;

  AnalyticsDataService(this._accountClient) {
    updateDispatcher = AnalyticsUpdateDispatcher(this);
    updateService = AnalyticsUpdateService(this);
    _initDatabase(_accountClient);
  }

  static const int _morphUnlockXP = AnalyticsConstants.xpForGreens;

  int _cacheVersion = 0;
  int _derivedCacheVersion = -1;
  DerivedAnalyticsDataModel? _cachedDerivedStats;

  _AnalyticsClient get _analyticsClientGetter {
    assert(_analyticsClient != null);
    return _analyticsClient!;
  }

  bool get isInitializing => !initCompleter.isCompleted;
  bool get hasInitError => initError != null;
  bool get isLogged => _analyticsClientGetter.client.isLogged();

  Room? _getAnalyticsRoomLocal(LanguageModel lang) =>
      _analyticsClientGetter.client.ownAnalyticsRoomLocal(lang: lang);

  Future<Room?> getAnalyticsRoom(LanguageModel lang) =>
      _analyticsClientGetter.client.getMyAnalyticsRoom(lang);

  Future<void> dispose() async {
    _syncController?.dispose();
    updateDispatcher.dispose();
    // Await the final dosage engagement-span flush BEFORE releasing this
    // account's resources, so its last span actually POSTs (isolated to this
    // account) rather than being dropped on teardown.
    await updateService.dispose();
    // AWAIT the database close/delete so dispose() doesn't resolve — and the
    // matrix teardown doesn't drop the service from its map — until the DB is
    // actually closed. Otherwise a rebuild could recreate the service and reopen
    // the SAME database while deletion is still running. A close/delete FAILURE
    // must not abort the account teardown (the loggedOut listener awaits this
    // before removing the client/store), so it is swallowed here.
    try {
      await _closeDatabase();
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
    }
  }

  void _invalidateCaches() {
    _cacheVersion++;
    _cachedDerivedStats = null;
  }

  Future<void> _initDatabase(Client client) async {
    _invalidateCaches();

    // #8525: pairs with the _closeDatabase crumb. Reopening REPLACES
    // _analyticsClient without closing the outgoing one, so a later
    // closed-store failure can also mean "a previous instance's connection
    // went away"; the crumb trail is what distinguishes the two.
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'AnalyticsDataService._initDatabase',
        data: {'replacedExisting': _analyticsClient != null},
      ),
    );

    final database = await analyticsDatabaseBuilder(
      "${client.clientName}_analytics",
    );
    _analyticsClient = _AnalyticsClient(client: client, database: database);

    if (client.isLogged()) {
      // Pin the dosage account mxid the moment we know we are logged in, BEFORE
      // the fallible analytics init below — otherwise an init failure would
      // leave the id unpinned and teardown would resolve '' and leak the tracker.
      updateService.pinAccountId();
      await _initAnalytics();
    } else {
      await client.onLoginStateChanged.stream.firstWhere(
        (state) => state == LoginState.loggedIn,
      );
      updateService.pinAccountId();
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
      final l2 = MatrixState.pangeaController.userController.userL2;
      final database = _analyticsClientGetter.database;
      final (analyticsUserId, storedLanguage, storedAnalyticsRoomId) = await (
        database.getUserID(),
        database.getCurrentLanguage(),
        l2 != null ? database.getAnalyticsRoomId() : Future<String?>.value(),
      ).wait;

      final analyticsRoomId = l2 != null
          ? _getAnalyticsRoomLocal(l2)?.id
          : null;

      if (analyticsUserId != client.userID ||
          storedLanguage == null ||
          (storedAnalyticsRoomId == null && analyticsRoomId != null)) {
        // If current language not set, analytics database needs be updated to include language flag, so clear it.
        // If stored analytics roomID not set, analytics database needs to be updated to include analytics roomID flag, so clear it.
        // If user ID doesn't match, this means that a different user has logged in since the last time the database was initialized,
        // so clear it to avoid showing another user's analytics.
        _clearLocalCaches();
        await _hardRefreshDatabase(lang: l2, analyticsRoomId: analyticsRoomId);
      } else if (l2 != null && storedLanguage != l2.langCodeShort) {
        // If the current language doesn't match the language in the database, this means that
        // the user has switched their L2 since the last time the database was initialized.
        // Clear local cache / merge table data.
        _clearLocalCaches();
        await _analyticsClientGetter.database.updateCurrentLanguage(
          l2.langCodeShort,
        );
        if (analyticsRoomId != null) {
          await _analyticsClientGetter.database.updateAnalyticsRoomId(
            analyticsRoomId,
          );
        }
      } else if (analyticsRoomId != null &&
          analyticsRoomId != storedAnalyticsRoomId) {
        // Stored language matches L2, but analytics roomIDs do not match.
        // The data in the database has diverged from the canonical analytics room, and must be fully refreshed.
        _clearLocalCaches();
        await _hardRefreshDatabase(lang: l2, analyticsRoomId: analyticsRoomId);
      }

      _syncController?.dispose();
      _syncController = AnalyticsSyncController(
        client: client,
        dataService: this,
      );

      if (l2 != null) {
        await _syncController!.bulkUpdate(l2.langCodeShort);
      }

      final resp = await client.getUserProfile(client.userID!);
      final analyticsProfile = AnalyticsProfileModel.fromJson(
        resp.additionalProperties,
      );

      if (l2 != null) {
        int xpOffset =
            analyticsProfile.xpOffsetByLanguage(l2.langCodeShort) ?? 0;
        if (xpOffset < 0) {
          ErrorHandler.logError(
            e: "Negative XP offset calculated during analytics update",
            s: StackTrace.current,
            data: {"offset": xpOffset, "language": l2.langCodeShort},
          );
          await MatrixState.pangeaController.userController.addXPOffset(
            -xpOffset,
            l2.langCodeShort,
          );
          xpOffset = 0;
        }
        await updateXPOffset(xpOffset, l2.langCodeShort);
      }

      _syncController!.start();
      updateService.start();

      if (l2 != null) {
        await _initMergeTable(l2.langCodeShort);
        await client.combineAnalyticsRooms(l2);
      }
    } catch (e, s) {
      Logs().e("Error initializing analytics: $e, $s");
      initError = e;
    } finally {
      Logs().i("Analytics database initialized.");
      initCompleter.complete();
      updateDispatcher.sendEmptyAnalyticsUpdate();
      updateDispatcher.sendActivityAnalyticsUpdate(null);
    }
  }

  /// Seed the merge table from the stored aggregates. Reads identifiers only
  /// ([AnalyticsDatabase.getAggregateIds]) — the table never needed the uses,
  /// and deserializing them was the last full-corpus parse on the init path.
  Future<void> _initMergeTable(String language) async {
    final database = _analyticsClientGetter.database;
    final (vocab, morph) = await (
      database.getAggregateIds(ConstructTypeEnum.vocab, language),
      database.getAggregateIds(ConstructTypeEnum.morph, language),
    ).wait;

    final blocked = blockedConstructs;
    _mergeTable.addIdentifiers(vocab, blocked);
    _mergeTable.addIdentifiers(morph, blocked);
  }

  Future<void> reinitialize() async {
    Logs().i("Reinitializing analytics database.");
    Sentry.addBreadcrumb(
      Breadcrumb(message: 'AnalyticsDataService.reinitialize'),
    );
    initError = null;
    initCompleter = Completer<void>();
    _clearLocalCaches();
    // Notify listeners immediately so the UI transitions from error to loading.
    updateDispatcher.sendEmptyAnalyticsUpdate();
    updateDispatcher.sendActivityAnalyticsUpdate(null);
    await _initDatabase(_analyticsClientGetter.client);
  }

  void _clearLocalCaches() {
    _invalidateCaches();
    _blockedCache.clear();
    _mergeTable.clear();
  }

  Future<void> _hardRefreshDatabase({
    required LanguageModel? lang,
    required String? analyticsRoomId,
  }) async {
    await _analyticsClientGetter.database.clear();

    await _analyticsClientGetter.database.updateUserID(
      _analyticsClientGetter.client.userID!,
    );

    if (lang == null) return;
    await _analyticsClientGetter.database.updateCurrentLanguage(
      lang.langCodeShort,
    );

    if (analyticsRoomId != null) {
      await _analyticsClientGetter.database.updateAnalyticsRoomId(
        analyticsRoomId,
      );
    }
  }

  Future<void> _closeDatabase() async {
    // Breadcrumb the close itself. #8525: a closed store poisons every later
    // analytics write, and the only way to tell an orderly teardown from a
    // close we did not initiate is whether this crumb precedes the failure.
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'AnalyticsDataService._closeDatabase',
        data: {'hadDatabase': _analyticsClient != null},
      ),
    );
    await _analyticsClient?.database.delete();
    _analyticsClient = null;
    _clearLocalCaches();
  }

  Future<void> _ensureInitialized() =>
      initCompleter.isCompleted ? Future.value() : initCompleter.future;

  int numConstructs(ConstructTypeEnum type) =>
      _mergeTable.uniqueConstructsByType(type);

  bool hasUsedConstruct(ConstructIdentifier id) =>
      _mergeTable.constructUsed(id);

  bool isConstructBlocked(ConstructIdentifier id) =>
      blockedConstructs.contains(id);

  int uniqueConstructsByType(ConstructTypeEnum type) =>
      _mergeTable.uniqueConstructsByType(type);

  /// See [BlockedConstructsCache] for what is memoized and why (#8433).
  final BlockedConstructsCache _blockedCache = BlockedConstructsCache();

  /// The user's blocked constructs for the current L2. Read-only: callers
  /// must not mutate the returned set (it is shared between reads).
  Set<ConstructIdentifier> get blockedConstructs {
    final client = _analyticsClientGetter.client;
    return _blockedCache.read(
      l2: MatrixState.pangeaController.userController.userL2?.langCodeShort,
      roomCount: client.rooms.length,
      roomById: client.getRoomById,
      resolveAnalyticsRoom: () => client.ownAnalyticsRoomLocalByL2,
    );
  }

  Future<void> waitForSync(String analyticsRoomID) async {
    await _syncController?.waitForSync(analyticsRoomID);
  }

  DerivedAnalyticsDataModel? get cachedDerivedData => _cachedDerivedStats;

  Future<DerivedAnalyticsDataModel> derivedData(String language) async {
    await _ensureInitialized();

    if (_cachedDerivedStats == null || _derivedCacheVersion != _cacheVersion) {
      _cachedDerivedStats = await _analyticsClientGetter.database
          .getDerivedStats(language);
      _derivedCacheVersion = _cacheVersion;
    }

    return _cachedDerivedStats!;
  }

  Future<DateTime?> getLastUpdatedAnalytics(String language) async {
    return _analyticsClientGetter.database.getLastEventTimestamp(language);
  }

  Future<List<OneConstructUse>> getUses(
    String language, {
    int? count,
    String? roomId,
    DateTime? since,
    List<ConstructUseTypeEnum>? types,
    bool filterCapped = true,
  }) async {
    await _ensureInitialized();
    final uses = await _analyticsClientGetter.database.getUses(
      language,
      count: count,
      roomId: roomId,
      since: since,
      types: types,
    );

    final blocked = blockedConstructs;

    // Every distinct, visible identifier in one batched aggregate read, so the
    // per-use loop below never awaits (#8420).
    final visibleIds = <ConstructIdentifier>{
      for (final use in uses)
        if (!blocked.contains(use.identifier) && !use.identifier.isInvalid)
          use.identifier,
    };
    final Map<ConstructIdentifier, DateTime?> cappedLastUseById = {};
    if (filterCapped && visibleIds.isNotEmpty) {
      final constructs = await getConstructUses(visibleIds.toList(), language);
      for (final entry in constructs.entries) {
        cappedLastUseById[entry.key] = entry.value.cappedLastUse;
      }
    }

    final List<OneConstructUse> filtered = [];
    for (final use in uses) {
      if (!visibleIds.contains(use.identifier)) continue;
      final cappedLastUse = cappedLastUseById[use.identifier];
      if (filterCapped &&
          (cappedLastUse != null && use.timeStamp.isAfter(cappedLastUse))) {
        continue;
      }
      filtered.add(use);
    }

    return filtered;
  }

  Future<List<OneConstructUse>> getLocalUses(String language) async {
    await _ensureInitialized();
    return _analyticsClientGetter.database.getLocalUses(language);
  }

  Future<int> getLocalConstructCount(String language) async {
    await _ensureInitialized();
    return _analyticsClientGetter.database.getLocalConstructCount(language);
  }

  Future<ConstructUses> getConstructUse(
    ConstructIdentifier id,
    String language,
  ) async {
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

    return _analyticsClientGetter.database.getConstructUse(ids, language);
  }

  Future<Map<ConstructIdentifier, ConstructUses>> getConstructUses(
    List<ConstructIdentifier> ids,
    String language,
  ) async {
    await _ensureInitialized();
    final Map<ConstructIdentifier, List<ConstructIdentifier>> request = {};
    final blocked = blockedConstructs;
    for (final id in ids) {
      if (blocked.contains(id)) continue;
      request[id] = _mergeTable.groupedIds(_mergeTable.resolve(id), blocked);
    }

    return _analyticsClientGetter.database.getConstructUses(request, language);
  }

  Future<Map<ConstructIdentifier, ConstructUses>> getAggregatedConstructs(
    ConstructTypeEnum type,
    String language,
  ) async {
    final combined = await _analyticsClientGetter.database
        .getAggregatedConstructs(type, language);

    final stopwatch = Stopwatch()..start();

    final cleaned = <ConstructIdentifier, ConstructUses>{};
    final blocked = blockedConstructs;
    for (final entry in combined) {
      final canonical = _mergeTable.resolve(entry.id);

      // Insert or merge
      final existing = cleaned[canonical];
      if (existing != null) {
        existing.merge(entry);
      } else if (!blocked.contains(canonical) && !canonical.isInvalid) {
        cleaned[canonical] = entry;
      }
    }

    stopwatch.stop();
    return cleaned;
  }

  /// The keys [getAggregatedConstructs] would return — every visible canonical
  /// construct of [type] — read from row identifiers alone
  /// ([AnalyticsDatabase.getAggregateIds]), so callers that only need the ids
  /// (practice distractors) skip deserializing every use.
  Future<Set<ConstructIdentifier>> getAggregatedConstructIds(
    ConstructTypeEnum type,
    String language,
  ) async {
    await _ensureInitialized();
    final ids = await _analyticsClientGetter.database.getAggregateIds(
      type,
      language,
    );
    final blocked = blockedConstructs;
    final result = <ConstructIdentifier>{};
    for (final id in ids) {
      final canonical = _mergeTable.resolve(id);
      if (blocked.contains(canonical) || canonical.isInvalid) continue;
      result.add(canonical);
    }
    return result;
  }

  /// The inverse of [getAggregatedConstructs]: only the constructs the user has
  /// blocked, for the deleted-vocab list. Every other fetcher on this service
  /// filters blocked ids OUT, so the undo surface needs its own read.
  ///
  /// Merge-table resolution is skipped on purpose — blocking removes an id from
  /// the table, so `resolve` would hand it straight back, and case-variants of a
  /// blocked lemma are separate entries in the blocked set too.
  ///
  /// Every blocked id of [type] gets a row even when the database has no uses
  /// for it (blocked on another device before this one ever saw the word), so a
  /// blocked construct can never become unrestorable.
  Future<Map<ConstructIdentifier, ConstructUses>> getBlockedConstructs(
    ConstructTypeEnum type,
    String language,
  ) async {
    await _ensureInitialized();
    final blocked = blockedConstructs;
    if (blocked.isEmpty) return {};

    final combined = await _analyticsClientGetter.database
        .getAggregatedConstructs(type, language);

    final result = <ConstructIdentifier, ConstructUses>{};
    for (final entry in combined) {
      if (!blocked.contains(entry.id) || entry.id.isInvalid) continue;
      final existing = result[entry.id];
      if (existing != null) {
        existing.merge(entry);
      } else {
        result[entry.id] = entry;
      }
    }

    for (final id in blocked) {
      if (id.type != type || id.isInvalid) continue;
      result.putIfAbsent(
        id,
        () => ConstructUses(
          uses: [],
          constructType: id.type,
          lemma: id.lemma,
          category: id.category,
        ),
      );
    }

    return result;
  }

  Future<int> getNewConstructCount(
    List<OneConstructUse> newConstructs,
    ConstructTypeEnum type,
    String language,
  ) async {
    await _ensureInitialized();
    final blocked = blockedConstructs;
    final uses = newConstructs
        .where(
          (c) =>
              c.constructType == type &&
              !blocked.contains(c.identifier) &&
              c.identifier.category != 'other',
        )
        .toList();

    final Map<ConstructIdentifier, int> constructPoints = {};
    for (final use in uses) {
      constructPoints[use.identifier] ??= 0;
      constructPoints[use.identifier] =
          constructPoints[use.identifier]! + use.xp;
    }

    final constructs = await getConstructUses(
      constructPoints.keys.toList(),
      language,
    );

    int newConstructCount = 0;
    for (final entry in constructPoints.entries) {
      final construct = constructs[entry.key]!;
      if (construct.points == entry.value) {
        newConstructCount++;
      }
    }

    return newConstructCount;
  }

  Future<void> updateXPOffset(int offset, String language) async {
    _invalidateCaches();
    await _analyticsClientGetter.database.updateXPOffset(offset, language);
  }

  Future<List<AnalyticsUpdateEvent>> updateLocalAnalytics(
    AnalyticsUpdate update,
    String language,
  ) async {
    final events = <AnalyticsUpdateEvent>[];
    final addedConstructs = update.addedConstructs
        .where((c) => c.category != 'other')
        .toList();
    final updateIds = addedConstructs.map((c) => c.identifier).toSet();

    final prevData = await derivedData(language);
    final prevConstructs = await getConstructUses(updateIds.toList(), language);

    _invalidateCaches();
    await _ensureInitialized();

    final blocked = blockedConstructs;
    final newUnusedConstructs = updateIds
        .where((id) => !hasUsedConstruct(id))
        .toSet();

    _mergeTable.addConstructsByUses(addedConstructs, blocked);
    await _analyticsClientGetter.database.updateLocalAnalytics(
      addedConstructs,
      language,
    );

    final newConstructs = await getConstructUses(updateIds.toList(), language);

    int points = 0;
    if (updateIds.isNotEmpty) {
      for (final id in updateIds) {
        final prevPoints = prevConstructs[id]?.points ?? 0;
        final newPoints = newConstructs[id]?.points ?? 0;
        points += (newPoints - prevPoints);
      }
      events.add(
        XPGainedEvent.fromUses(addedConstructs, points, update.targetID),
      );
    }

    final newData = prevData.addXP(points);
    await _analyticsClientGetter.database.updateDerivedStats(newData, language);

    // Update public profile each time that new analytics are added.
    // If the level hasn't changed, this will not send an update to the server.
    // Do this on all updates (not just on level updates) to account for cases
    // of target language updates being missed (https://github.com/pangeachat/client/issues/2006)
    MatrixState.pangeaController.userController.updateAnalyticsProfile(
      languageCode: language,
      level: newData.level,
    );

    if (newData.level > prevData.level) {
      events.add(LevelUpEvent(prevData.level, newData.level));
    } else if (newData.level < prevData.level || newData.totalXP < 0) {
      final lowerLevelXP = newData.totalXP < 0
          ? 0
          : DerivedAnalyticsDataModel.calculateXpWithLevel(prevData.level);

      final offset = lowerLevelXP - newData.totalXP;
      if (offset < 0) {
        ErrorHandler.logError(
          e: "Negative XP offset calculated during analytics update",
          s: StackTrace.current,
          data: {
            "offset": offset,
            "prevLevel": prevData.level,
            "newLevel": newData.level,
            "prevXP": prevData.totalXP,
            "newXP": newData.totalXP,
          },
        );
      } else {
        await MatrixState.pangeaController.userController.addXPOffset(
          offset,
          language,
        );
        // Mirrors whatever the public profile ended up holding. Null when the
        // offset was not applied there — nothing loaded yet, or a profile
        // belonging to another account (#8531) — and the local copy must then
        // stay put too, rather than drifting away from the published one.
        final xpOffset = MatrixState
            .pangeaController
            .userController
            .publicProfile
            ?.analytics
            .xpOffsetByLanguage(language);
        if (xpOffset != null) {
          await updateXPOffset(xpOffset, language);
        }
      }
    }

    final newUnlockedMorphs = updateIds.where((id) {
      if (id.type != ConstructTypeEnum.morph) return false;
      final prevPoints = prevConstructs[id]?.points ?? 0;
      final newPoints = newConstructs[id]?.points ?? 0;
      return prevPoints < _morphUnlockXP && newPoints >= _morphUnlockXP;
    }).toSet();

    if (newUnlockedMorphs.isNotEmpty) {
      events.add(MorphUnlockedEvent(newUnlockedMorphs, update.targetID));
    }

    for (final entry in newConstructs.entries) {
      final prevConstruct = prevConstructs[entry.key];
      if (prevConstruct == null) continue;

      final prevLevel = prevConstruct.lemmaCategory;
      final newLevel = entry.value.lemmaCategory;
      if (newLevel.xpNeeded > prevLevel.xpNeeded) {
        events.add(ConstructLevelUpEvent(entry.key, newLevel, update.targetID));
      }
    }

    if (newUnusedConstructs.isNotEmpty) {
      events.add(NewConstructsEvent(newUnusedConstructs));
    }

    return events;
  }

  Future<void> updateServerAnalytics(
    List<ConstructAnalyticsEvent> events,
    String language,
  ) async {
    _invalidateCaches();
    final blocked = blockedConstructs;
    for (final event in events) {
      _mergeTable.addConstructsByUses(event.content.uses, blocked);
    }
    await _analyticsClientGetter.database.updateServerAnalytics(
      events,
      language,
    );
    await _recomputeTotalXP(language);
  }

  /// Recomputes the language's XP total and level from the current aggregate.
  ///
  /// Reads per-row uncapped xp sums straight from the aggregate JSON
  /// ([AnalyticsDatabase.getAggregateXPSums]) and folds them with
  /// [foldTotalXP] — the same grouping, blocked/invalid filter and per-construct
  /// cap that [getAggregatedConstructs] applies, without deserializing every
  /// stored use (#8418).
  Future<void> _recomputeTotalXP(String language) async {
    final db = _analyticsClientGetter.database;
    final sums = await Future.wait([
      db.getAggregateXPSums(ConstructTypeEnum.vocab, language),
      db.getAggregateXPSums(ConstructTypeEnum.morph, language),
    ]);
    final totalXP = foldTotalXP(
      sums.expand((s) => s),
      resolve: _mergeTable.resolve,
      blocked: blockedConstructs,
    );

    // Store first, then publish the level the STORE now reports. The mirror
    // has to agree with the analytics bar, and the bar renders
    // DerivedAnalyticsDataModel.level — which is computed over totalXP PLUS the
    // language's XP offset. Publishing calculateLevelWithXp(totalXP) here
    // dropped that offset, so every learner carrying one (any learner whose
    // level protection has ever engaged) had a mirror sitting below their own
    // bar, re-published on every sync round-trip (#8582).
    await db.updateTotalXP(totalXP, language);
    _invalidateCaches();

    await MatrixState.pangeaController.userController.updateAnalyticsProfile(
      languageCode: language,
      level: (await derivedData(language)).level,
    );
  }

  /// Total XP over per-row uncapped xp [sums]: rows are grouped by their
  /// merge-table canonical id ([resolve]), groups whose canonical is blocked or
  /// invalid are dropped, and each remaining group contributes
  /// `min(sum, xpForFlower)` — exactly what summing [ConstructUses.points]
  /// over [getAggregatedConstructs] yields.
  @visibleForTesting
  static int foldTotalXP(
    Iterable<({ConstructIdentifier id, int xp})> sums, {
    required ConstructIdentifier Function(ConstructIdentifier) resolve,
    required Set<ConstructIdentifier> blocked,
  }) {
    final byCanonical = <ConstructIdentifier, int>{};
    for (final row in sums) {
      final canonical = resolve(row.id);
      if (blocked.contains(canonical) || canonical.isInvalid) continue;
      byCanonical[canonical] = (byCanonical[canonical] ?? 0) + row.xp;
    }
    var total = 0;
    for (final xp in byCanonical.values) {
      total += min(xp, AnalyticsConstants.xpForFlower);
    }
    return total;
  }

  Future<void> updateBlockedConstructs(
    Set<ConstructIdentifier> constructIds,
    String language,
  ) async {
    await _ensureInitialized();
    for (final constructId in constructIds) {
      _mergeTable.removeConstruct(constructId);
    }
    _invalidateCaches();
    await _recomputeTotalXP(language);
    _invalidateCaches();
  }

  Future<void> updateRestoredConstructs(
    Set<ConstructIdentifier> constructIds,
    String language,
  ) async {
    await _ensureInitialized();
    await _initMergeTable(language);
    _invalidateCaches();
    await _recomputeTotalXP(language);
    _invalidateCaches();
  }

  /// Drop the local (not-yet-uploaded) uses and aggregates, then re-derive
  /// the XP total. This runs right after the uploaded copy has echoed back
  /// from the analytics room; the recompute that echo triggered saw the
  /// uses on both sides, so the total is settled here rather than on the
  /// next unrelated sync.
  Future<void> clearLocalAnalytics(String language) async {
    _invalidateCaches();
    await _ensureInitialized();
    await _analyticsClientGetter.database.clearLocalConstructData(language);
    _invalidateCaches();
    await _recomputeTotalXP(language);
  }
}
