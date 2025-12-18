import 'dart:async';

import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_stream_service.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_settings/analytics_settings_extension.dart';
import 'package:fluffychat/pangea/analytics_settings/analytics_settings_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/user/user_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsUpdateService {
  static const int _maxMessagesCached = 10;

  final AnalyticsDataService dataService;

  AnalyticsUpdateService(this.dataService);

  Completer<void>? _updateCompleter;

  Future<void> onUpdateLanguages(LanguageUpdate update) async {
    await sendLocalAnalyticsToAnalyticsRoom(
      l2Override: update.prevTargetLang,
    );
    await dataService.reinitialize();

    final data = await dataService.derivedData;
    MatrixState.pangeaController.userController
        .updateAnalyticsProfile(level: data.level);
  }

  Future<void> addAnalytics(
    String? targetID,
    List<OneConstructUse> newConstructs,
  ) async {
    await dataService.streamService.sendConstructAnalyticsUpdate(
      AnalyticsUpdate(
        newConstructs,
        targetID: targetID,
      ),
    );

    final localConstructCount = await dataService.getLocalConstructCount();
    final lastUpdated = await dataService.getLastUpdatedAnalytics();
    final difference = DateTime.now().difference(lastUpdated ?? DateTime.now());

    if (localConstructCount > _maxMessagesCached || difference.inMinutes > 10) {
      sendLocalAnalyticsToAnalyticsRoom();
    }
  }

  Future<void> sendLocalAnalyticsToAnalyticsRoom({
    LanguageModel? l2Override,
  }) async {
    if (!(_updateCompleter?.isCompleted ?? true)) {
      await _updateCompleter!.future;
      return;
    }
    _updateCompleter = Completer<void>();
    try {
      await _updateAnalytics(l2Override: l2Override);
      dataService.clearLocalAnalytics();
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

  Future<void> _updateAnalytics({LanguageModel? l2Override}) async {
    final localConstructs = await dataService.getLocalUses();
    if (localConstructs.isEmpty) return;

    // if missing important info, don't send analytics. Could happen if user just signed up.
    final l2 = l2Override ?? MatrixState.pangeaController.userController.userL2;
    if (l2 == null) return;

    // analytics room for the user and current target language
    final analyticsRoom = await dataService.getAnalyticsRoom(l2);

    // and send cached analytics data to the room
    await analyticsRoom?.sendConstructsEvent(localConstructs);
  }

  Future<void> sendActivityAnalytics(String roomId) async {
    final l2 = MatrixState.pangeaController.userController.userL2;
    if (l2 == null) return;

    // analytics room for the user and current target language
    final analyticsRoom = await dataService.getAnalyticsRoom(l2);
    if (analyticsRoom == null) return;

    await analyticsRoom.addActivityRoomId(roomId);
    dataService.streamService.sendActivityAnalyticsUpdate(roomId);
  }

  Future<void> blockConstruct(ConstructIdentifier constructId) async {
    final l2 = MatrixState.pangeaController.userController.userL2;
    if (l2 == null) return;

    // analytics room for the user and current target language
    final analyticsRoom = await dataService.getAnalyticsRoom(l2);
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
  }
}
