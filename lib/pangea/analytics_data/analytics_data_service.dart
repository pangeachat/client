import 'dart:async';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_data/analytics_database.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_database_builder.dart';
import 'package:fluffychat/pangea/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_event.dart';
import 'package:fluffychat/pangea/analytics_misc/put_analytics_controller.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
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

class AnalyticsDataService {
  _AnalyticsClient? _analyticsClient;
  StreamSubscription? _serverAnalyticsUpdateListener;

  AnalyticsDataService(Client client) {
    _initDatabase(client).then((_) => _addAnalyticsUpdateListener());
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

  Room? get _analyticsRoom {
    final l2 = MatrixState.pangeaController.userController.userL2;
    if (l2 == null) {
      return null;
    }
    return _analyticsClient?.client.analyticsRoomLocal(l2);
  }

  void dispose() {
    _serverAnalyticsUpdateListener?.cancel();
    _closeDatabase();
  }

  void _addAnalyticsUpdateListener() {
    _serverAnalyticsUpdateListener = _analyticsClientGetter.client.onSync.stream
        .listen(_updateServerAnalytics);
  }

  void _clearCache() {
    _cachedDerivedStats = null;
  }

  Future<void> _initDatabase(Client client) async {
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
    final client = _analyticsClientGetter.client;
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }

    final resp = await client.getUserProfile(client.userID!);
    final analyticsProfile =
        AnalyticsProfileModel.fromJson(resp.additionalProperties);

    await updateXPOffset(analyticsProfile.xpOffset ?? 0);
    await _bulkUpdateAnalytics();
  }

  Future<void> _closeDatabase() async {
    await _analyticsClient?.database.delete();
    _analyticsClient = null;
  }

  Future<DerivedAnalyticsDataModel> get derivedData async {
    _cachedDerivedStats ??=
        await _analyticsClientGetter.database.getDerivedStats();
    return _cachedDerivedStats!;
  }

  Future<List<ConstructUses>> getMergedCombinedAggregates() async {
    final combined =
        await _analyticsClientGetter.database.getCombinedAggregates();

    final Map<String, String?> mergeTable = {};
    final Map<String, ConstructUses> cleaned = {};

    final keys = combined.keys.toList();
    for (final key in keys) {
      if (mergeTable.containsKey(key)) continue;
      final parts = key.split('|');
      if (parts.length != 3) {
        continue;
      }

      final lemma = parts[0];
      final constructType = parts[1];
      final category = parts[2];
      if (category != 'other') continue;

      mergeTable[key] = keys.firstWhereOrNull(
        (k) {
          final p = k.split("|");
          return p[0] == lemma && p[1] == constructType && p[2] != 'other';
        },
      );
    }

    for (final entry in combined.entries) {
      final key = mergeTable[entry.key] ?? entry.key;
      final dest = cleaned[key];
      if (dest != null) {
        dest.uses.addAll(entry.value.uses);
        if (entry.value.lastUsed != null) {
          dest.setLastUsed(entry.value.lastUsed!);
        }
        cleaned[key] = dest;
      } else {
        cleaned[key] = entry.value;
      }
    }

    return cleaned.values.toList();
  }

  Future<void> updateXPOffset(int offset) async {
    await _analyticsClientGetter.database.updateXPOffset(offset);
    _clearCache();
  }

  Future<void> updateLocalAnalytics(
    AnalyticsUpdate update,
  ) async {
    if (update.type != AnalyticsUpdateType.local) {
      return;
    }

    _clearCache();
    await _analyticsClientGetter.database.updateLocalAnalytics(
      update.newConstructs,
    );
  }

  Future<void> clearLocalAnalytics() =>
      _analyticsClientGetter.database.clearLocalConstructData();

  Future<void> _updateServerAnalytics(
    SyncUpdate update,
  ) async {
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
  }

  Future<void> _bulkUpdateAnalytics() async {
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
}
