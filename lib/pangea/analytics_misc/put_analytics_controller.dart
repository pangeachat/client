import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_settings/analytics_settings_extension.dart';
import 'package:fluffychat/pangea/analytics_settings/analytics_settings_model.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/user/user_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum AnalyticsUpdateType { server, local }

/// handles the processing of analytics for
/// 1) messages sent by the user and
/// 2) constructs used by the user, both in sending messages and doing practice activities
class PutAnalyticsController {
  late PangeaController _pangeaController;
  StreamController<AnalyticsUpdate> analyticsUpdateStream =
      StreamController.broadcast();

  ValueNotifier<List<String>> savedActivitiesNotifier = ValueNotifier([]);
  ValueNotifier<ConstructIdentifier?> blockedConstructsNotifier =
      ValueNotifier(null);

  StreamSubscription? _languageStream;
  Timer? _updateTimer;

  Client get _client => _pangeaController.matrixState.client;

  /// the last time that matrix analytics events were updated for the user's current l2
  DateTime? lastUpdated;

  /// Last updated completer. Used to wait for the last
  /// updated time to be set before setting analytics data.
  Completer<DateTime?> lastUpdatedCompleter = Completer<DateTime?>();

  /// the max number of messages that will be cached before
  /// an automatic update is triggered
  final int _maxMessagesCached = 10;

  /// the number of minutes before an automatic update is triggered
  final int _minutesBeforeUpdate = 5;

  /// the time since the last update that will trigger an automatic update
  final Duration _timeSinceUpdate = const Duration(days: 1);

  PutAnalyticsController(PangeaController pangeaController) {
    _pangeaController = pangeaController;
  }

  void initialize() {
    _languageStream ??= _pangeaController.userController.languageStream.stream
        .listen(_onUpdateLanguages);
    _refreshAnalyticsIfOutdated();
  }

  /// Reset analytics last updated time to null.
  void dispose() {
    _updateTimer?.cancel();
    lastUpdated = null;
    lastUpdatedCompleter = Completer<DateTime?>();
    _languageStream?.cancel();
    _languageStream = null;
    MatrixState.pangeaController.getAnalytics.clearMessagesCache();
  }

  /// If analytics haven't been updated in the last day, update them
  Future<void> _refreshAnalyticsIfOutdated() async {
    // don't set anything is the user is not logged in
    if (_client.userID == null) return;
    try {
      // if lastUpdated hasn't been set yet, set it
      lastUpdated ??=
          await _pangeaController.getAnalytics.myAnalyticsLastUpdated();
    } catch (err, s) {
      ErrorHandler.logError(
        s: s,
        e: err,
        m: "Failed to get last updated time for analytics",
        data: {},
      );
    } finally {
      // if this is the initial load, complete the lastUpdatedCompleter
      if (!lastUpdatedCompleter.isCompleted) {
        lastUpdatedCompleter.complete(lastUpdated);
      }
    }

    final DateTime yesterday = DateTime.now().subtract(_timeSinceUpdate);
    if (lastUpdated?.isBefore(yesterday) ?? true) {
      debugPrint("analytics out-of-date, updating");
      await sendLocalAnalyticsToAnalyticsRoom();
    }
  }

  /// Given new construct uses, format and cache
  /// the data locally and reset the update timer
  /// Decide whether to update the analytics room
  void addAnalytics(
    List<OneConstructUse> constructs, {
    String? eventId,
    String? roomId,
    String? targetId,
  }) {
    final level = _pangeaController.getAnalytics.constructListModel.level;
    _addLocalMessage(eventId, List.from(constructs)).then(
      (_) => _sendAnalytics(level, targetId, constructs),
    );
  }

  /// Add a list of construct uses for a new message to the local
  /// cache of recently sent messages
  Future<void> _addLocalMessage(
    String? cacheKey,
    List<OneConstructUse> constructs,
  ) async {
    try {
      final currentCache = _pangeaController.getAnalytics.messagesSinceUpdate;
      constructs.addAll(currentCache[cacheKey] ?? []);

      // if this is not a draft message, add the eventId to the metadata
      // if it's missing (it will be missing for draft constructs)
      if (cacheKey != null) {
        constructs = constructs.map((construct) {
          if (construct.metadata.eventId != null) return construct;
          construct.metadata.eventId = cacheKey;
          return construct;
        }).toList();
      }

      cacheKey ??= Object.hashAll(constructs).toString();
      currentCache[cacheKey] = constructs;

      await _setMessagesSinceUpdate(currentCache);
    } catch (e, s) {
      ErrorHandler.logError(
        e: PangeaWarningError("Failed to add message since update: $e"),
        s: s,
        m: 'Failed to add message since update for eventId: $cacheKey',
        data: {
          "cacheKey": cacheKey,
        },
      );
    }
  }

  /// Handles cleanup after adding a new message to the local cache.
  /// If the addition brought the total number of messages in the cache
  /// to the max, or if the addition triggered a level-up, update the analytics.
  /// Otherwise, add a local update to the alert stream.
  void _sendAnalytics(
    int prevLevel,
    String? targetID,
    List<OneConstructUse> newConstructs,
  ) {
    // cancel the last timer that was set on message event and
    // reset it to fire after _minutesBeforeUpdate minutes
    _updateTimer?.cancel();
    _updateTimer = Timer(Duration(minutes: _minutesBeforeUpdate), () {
      debugPrint("timer fired, updating analytics");
      sendLocalAnalyticsToAnalyticsRoom();
    });

    if (_pangeaController.getAnalytics.messagesSinceUpdate.length >
        _maxMessagesCached) {
      debugPrint("reached max messages, updating");
      sendLocalAnalyticsToAnalyticsRoom();
      return;
    }
    analyticsUpdateStream.add(
      AnalyticsUpdate(
        AnalyticsUpdateType.local,
        newConstructs,
        targetID: targetID,
      ),
    );
  }

  Future<void> _onUpdateLanguages(LanguageUpdate update) async {
    await sendLocalAnalyticsToAnalyticsRoom(
      l2Override: update.prevTargetLang,
    );
    _pangeaController.resetAnalytics().then((_) {
      final level = _pangeaController.getAnalytics.constructListModel.level;
      _pangeaController.userController.updateAnalyticsProfile(level: level);
    });
  }

  /// Save the local cache of recently sent constructs to the local storage
  Future<void> _setMessagesSinceUpdate(
    Map<String, List<OneConstructUse>> cache,
  ) async {
    final formattedCache = {};
    for (final entry in cache.entries) {
      final constructJsons = entry.value.map((e) => e.toJson()).toList();
      formattedCache[entry.key] = constructJsons;
    }
    await MatrixState.pangeaController.getAnalytics
        .setMessagesCache(formattedCache);
  }

  /// Prevent concurrent updates to analytics
  Completer<void>? _updateCompleter;

  /// Updates learning analytics.
  ///
  /// This method is responsible for updating the analytics. It first checks if an update is already in progress
  /// by checking the completion status of the [_updateCompleter]. If an update is already in progress, it waits
  /// for the completion of the previous update and returns. Otherwise, it creates a new [_updateCompleter] and
  /// proceeds with the update process. If the update is successful, it clears any messages that were received
  /// since the last update and notifies the [analyticsUpdateStream].
  Future<void> sendLocalAnalyticsToAnalyticsRoom({
    onLogout = false,
    LanguageModel? l2Override,
  }) async {
    if (_client.userID == null) return;
    if (_pangeaController.getAnalytics.messagesSinceUpdate.isEmpty) return;

    if (!(_updateCompleter?.isCompleted ?? true)) {
      await _updateCompleter!.future;
      return;
    }
    _updateCompleter = Completer<void>();
    try {
      await _updateAnalytics(l2Override: l2Override);
      MatrixState.pangeaController.getAnalytics.clearMessagesCache();

      lastUpdated = DateTime.now();
      analyticsUpdateStream.add(
        AnalyticsUpdate(
          AnalyticsUpdateType.server,
          [],
          isLogout: onLogout,
        ),
      );
    } catch (err, s) {
      ErrorHandler.logError(
        e: err,
        m: "Failed to update analytics",
        s: s,
        data: {
          "l2Override": l2Override,
        },
      );
    } finally {
      _updateCompleter?.complete();
      _updateCompleter = null;
    }
  }

  /// Updates the analytics by sending cached analytics data to the analytics room.
  /// The analytics room is determined based on the user's current target language.
  Future<void> _updateAnalytics({LanguageModel? l2Override}) async {
    // if there's no cached construct data, there's nothing to send
    final cachedConstructs = _pangeaController.getAnalytics.messagesSinceUpdate;
    final bool onlyDraft = cachedConstructs.length == 1 &&
        cachedConstructs.keys.single.startsWith('draft');
    if (cachedConstructs.isEmpty || onlyDraft) return;

    // if missing important info, don't send analytics. Could happen if user just signed up.
    final l2 = l2Override ?? _pangeaController.userController.userL2;
    if (l2 == null || _client.userID == null) return;

    // analytics room for the user and current target language
    final Room? analyticsRoom = await _client.getMyAnalyticsRoom(l2);

    // and send cached analytics data to the room
    await analyticsRoom?.sendConstructsEvent(
      _pangeaController.getAnalytics.locallyCachedSentConstructs,
    );
  }

  Future<void> sendActivityAnalytics(String roomId) async {
    if (_client.userID == null) return;
    if (_pangeaController.userController.userL2 == null) return;

    final Room? analyticsRoom = await _client.getMyAnalyticsRoom(
      _pangeaController.userController.userL2!,
    );
    if (analyticsRoom == null) return;
    await analyticsRoom.addActivityRoomId(roomId);
    savedActivitiesNotifier.value = analyticsRoom.activityRoomIds;
  }

  Future<void> blockConstruct(ConstructIdentifier constructId) async {
    if (_pangeaController.matrixState.client.userID == null) return;
    if (_pangeaController.userController.userL2 == null) return;

    final Room? analyticsRoom = await _client.getMyAnalyticsRoom(
      _pangeaController.userController.userL2!,
    );
    if (analyticsRoom == null) return;

    final current = analyticsRoom.analyticsSettings ??
        const AnalyticsSettingsModel(blockedConstructs: {});

    final blockedConstructs = current.blockedConstructs;
    final updated = current.copyWith(
      blockedConstructs: {
        ...blockedConstructs,
        constructId,
      },
    );

    await analyticsRoom.setAnalyticsSettings(updated);
    blockedConstructsNotifier.value = constructId;
  }
}

class AnalyticsUpdate {
  final AnalyticsUpdateType type;
  final List<OneConstructUse> newConstructs;
  final bool isLogout;
  final String? targetID;

  AnalyticsUpdate(
    this.type,
    this.newConstructs, {
    this.isLogout = false,
    this.targetID,
  });
}
