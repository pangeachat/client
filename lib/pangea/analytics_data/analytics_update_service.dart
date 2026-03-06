import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_misc/saved_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/user_lemma_info_extension.dart';
import 'package:fluffychat/pangea/analytics_settings/analytics_settings_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/user/user_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsUpdateService {
  static const int _maxMessagesCached = 10;

  final AnalyticsDataService dataService;

  AnalyticsUpdateService(this.dataService) {
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => sendLocalAnalyticsToAnalyticsRoom(),
    );
  }

  Completer<void>? _updateCompleter;
  Timer? _periodicTimer;

  void dispose() {
    _periodicTimer?.cancel();
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

    await analyticsRoom.addActivityRoomId(roomId);
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
