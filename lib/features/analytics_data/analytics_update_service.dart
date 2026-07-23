import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_settings_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/lemmas/user_lemma_info_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsUpdateService with WidgetsBindingObserver {
  static const int _maxMessagesCached = 10;

  final AnalyticsDataService dataService;

  /// Test-only injected tracker; when set, [dispose] flushes it directly instead
  /// of the per-account registry.
  final DosageEngagementTracker? _injectedTracker;

  AnalyticsUpdateService(this.dataService, {DosageEngagementTracker? tracker})
    : _injectedTracker = tracker {
    // Pin the account mxid AT CONSTRUCTION when the client is already logged in.
    // The authoritative pin is [pinAccountId] called from
    // [AnalyticsDataService._initDatabase] the moment `loggedIn` is observed
    // (before the fallible analytics init); this and [start] are backstops.
    pinAccountId();
  }

  /// The account mxid, PINNED the moment the client is logged in (from
  /// [AnalyticsDataService._initDatabase], before the fallible analytics init;
  /// with construction + [start] as backstops) and retained — so teardown
  /// resolves it even after the SDK nulls userID in `clear()` ahead of
  /// `loggedOut`, and even when the analytics init fails before `start`. Not a
  /// raw constructor snapshot (that can precede login on a fresh startup with an
  /// unlogged default client); falls back to a live read until pinned.
  String? _pinnedAccountId;
  String get _accountUserId =>
      _pinnedAccountId ?? dataService.accountUserId ?? '';

  /// Latches the account mxid from the live account id when one is available.
  /// Idempotent; a no-op before login. Called at the earliest logged-in point.
  void pinAccountId() {
    final live = dataService.accountUserId;
    if (live != null && live.isNotEmpty) _pinnedAccountId = live;
  }

  /// This account's engagement tracker (heartbeat/background flush target).
  DosageEngagementTracker? get _tracker =>
      _injectedTracker ?? DosageEngagementTracker.forAccount(_accountUserId);

  Completer<void>? _updateCompleter;
  Timer? _periodicTimer;

  void start() {
    // Backstop pin (the authoritative pin is at the loggedIn observation in
    // _initDatabase): covers any path where that didn't run before start.
    pinAccountId();
    // Piggyback app-lifecycle hooks for the dosage engagement tracker; the
    // 5-minute tick below is its heartbeat flush. Idempotent re-registration
    // so a restart can't stack observers.
    WidgetsBinding.instance
      ..removeObserver(this)
      ..addObserver(this);
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      // Heartbeat flush of any open engagement span (no-op when none / dark).
      unawaited(_tracker?.flushOpenSpan() ?? Future.value());
      if (!dataService.isLogged) {
        ErrorHandler.logError(
          e: "User not logged in on periodic analytics update",
          data: {},
        );
        _periodicTimer?.cancel();
        return;
      }
      // Skip if user hasn't set their L2 yet (e.g., mid-onboarding)
      if (_l2 == null) return;
      sendLocalAnalyticsToAnalyticsRoom();
    });
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();
    // Await the final flush so the last open engagement span is actually sent —
    // callers dispose BEFORE invalidating the bearer, so the POST uses a valid
    // token. Dispose the account's tracker via the registry (isolated to this
    // account); a test-injected tracker is flushed directly.
    final injected = _injectedTracker;
    if (injected != null) {
      await injected.flushOpenSpan();
    } else {
      await DosageEngagementTracker.disposeAccount(_accountUserId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A span represents FOREGROUND engagement, so any move off `resumed`
    // (inactive/paused/detached/hidden) closes and flushes it; it reopens on
    // the next learner activity.
    if (state != AppLifecycleState.resumed) {
      unawaited(_tracker?.flushOpenSpan() ?? Future.value());
    }
  }

  LanguageModel? get _l2 => MatrixState.pangeaController.userController.userL2;

  Future<Room?> _getAnalyticsRoom({LanguageModel? l2Override}) async {
    final l2 = l2Override ?? _l2;
    if (l2 == null) return null;

    final analyticsRoom = await dataService.getAnalyticsRoom(l2);
    return analyticsRoom;
  }

  Future<void> onUpdateLanguages(LanguageUpdate update) async {
    await sendLocalAnalyticsToAnalyticsRoom(l2Override: update.prevTargetLang);
    await dataService.reinitialize();

    final data = await dataService.derivedData(update.targetLang.langCodeShort);
    MatrixState.pangeaController.userController.updateAnalyticsProfile(
      level: data.level,
    );
  }

  Future<void> addAnalytics(
    String? targetID,
    List<OneConstructUse> newConstructs,
    String language, {
    bool forceUpdate = false,
  }) async {
    await dataService.updateDispatcher.sendLocalAnalyticsUpdate(
      AnalyticsUpdate(newConstructs, targetID: targetID),
      language,
    );

    final localConstructCount = await dataService.getLocalConstructCount(
      language,
    );
    final lastUpdated = await dataService.getLastUpdatedAnalytics(language);
    final difference = DateTime.now().difference(lastUpdated ?? DateTime.now());

    if (forceUpdate ||
        localConstructCount > _maxMessagesCached ||
        difference.inMinutes > 10) {
      sendLocalAnalyticsToAnalyticsRoom();
    }
  }

  Future<void> sendLocalAnalyticsToAnalyticsRoom({
    LanguageModel? l2Override,
  }) async {
    final lang = l2Override ?? _l2;
    if (lang == null) {
      ErrorHandler.logError(
        e: "No L2 language set for user",
        m: "Cannot send local analytics to analytics room",
        data: {"l2Override": l2Override},
        level: SentryLevel.warning,
      );
      return;
    }

    final inProgress =
        _updateCompleter != null && !_updateCompleter!.isCompleted;

    if (inProgress) {
      await _updateCompleter!.future;
      return;
    }

    _updateCompleter = Completer<void>();
    try {
      await _updateAnalytics(lang);
      await dataService.clearLocalAnalytics(lang.langCodeShort);
    } catch (err, s) {
      ErrorHandler.logError(
        e: err,
        m: "Failed to update analytics",
        s: s,
        data: {"l2Override": l2Override},
      );
    } finally {
      _updateCompleter?.complete();
      _updateCompleter = null;
    }
  }

  Future<void> _updateAnalytics(LanguageModel language) async {
    final localConstructs = await dataService.getLocalUses(
      language.langCodeShort,
    );
    if (localConstructs.isEmpty) return;
    final analyticsRoom = await _getAnalyticsRoom(l2Override: language);
    if (analyticsRoom == null) {
      debugPrint(
        "No analytics room found for L2 Override: ${language.langCodeShort}",
      );
      return;
    }

    // and send cached analytics data to the room
    final future = dataService.waitForSync(analyticsRoom.id);
    await analyticsRoom.sendConstructsEvent(localConstructs);
    await future;
  }

  Future<void> sendActivityAnalytics(String roomId, LanguageModel lang) async {
    final analyticsRoom = await _getAnalyticsRoom(l2Override: lang);
    if (analyticsRoom == null) return;

    await analyticsRoom.addActivityRoomIds({roomId});
  }

  Future<void> blockConstructs(List<ConstructIdentifier> constructIds) async {
    final analyticsRoom = await _getAnalyticsRoom();
    if (analyticsRoom == null) return;

    final current = analyticsRoom.analyticsSettings;
    final blockedConstructs = current.blockedConstructs;
    final updated = current.copyWith(
      blockedConstructs: {...blockedConstructs, ...constructIds},
    );

    await analyticsRoom.setAnalyticsSettings(updated);
  }

  Future<void> setLemmaInfo(
    ConstructIdentifier constructId, {
    String? emoji,
    String? meaning,
  }) async {
    final analyticsRoom = await _getAnalyticsRoom();
    if (analyticsRoom == null) return;

    final userLemmaInfo = analyticsRoom.getUserSetLemmaInfo(constructId);
    final updated = userLemmaInfo.copyWith(
      emojis: emoji == null ? null : [emoji],
      meaning: meaning,
    );
    if (userLemmaInfo == updated) return;

    try {
      await analyticsRoom.setUserSetLemmaInfo(constructId, updated);
    } catch (err, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(e: err, data: userLemmaInfo.toJson(), s: s);
    }
  }
}
