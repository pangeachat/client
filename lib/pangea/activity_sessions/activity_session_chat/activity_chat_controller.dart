import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_analytics_repo.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_analytics_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityChatController {
  final String userID;
  final Room room;

  ActivityChatController({required this.userID, required this.room}) {
    init();
  }

  StreamSubscription? _analyticsSubscription;
  bool _disposed = false;

  final ScrollController carouselController = ScrollController();
  final ValueNotifier<Set<String>> usedVocab = ValueNotifier({});
  final ValueNotifier<ActivityRoleModel?> highlightedRole = ValueNotifier(null);
  final ValueNotifier<bool> showInstructions = ValueNotifier(false);
  final ValueNotifier<bool> showActivityDropdown = ValueNotifier(false);
  final ValueNotifier<bool> hasRainedConfetti = ValueNotifier(false);

  void init() {
    _updateUsedVocab();
    _analyticsSubscription = MatrixState
        .pangeaController
        .matrixState
        .analyticsDataService
        .updateDispatcher
        .constructUpdateStream
        .stream
        .listen((_) => _updateUsedVocab());
  }

  void dispose() {
    _disposed = true;
    carouselController.dispose();
    _analyticsSubscription?.cancel();
    usedVocab.dispose();
    highlightedRole.dispose();
    showInstructions.dispose();
    showActivityDropdown.dispose();
    hasRainedConfetti.dispose();
  }

  void highlightRole(ActivityRoleModel role) {
    if (!_disposed) {
      highlightedRole.value = role;
    }
  }

  void toggleShowInstructions() {
    if (!_disposed) {
      showInstructions.value = !showInstructions.value;
    }
  }

  void toggleShowDropdown() {
    if (!_disposed) {
      showActivityDropdown.value = !showActivityDropdown.value;
    }
  }

  void setHasRainedConfetti(bool show) {
    if (!_disposed) {
      hasRainedConfetti.value = show;
    }
  }

  Future<void> _updateUsedVocab() async {
    try {
      final analytics = await getActivityAnalytics();
      if (!_disposed) {
        usedVocab.value =
            analytics.constructs[userID]
                ?.constructsOfType(ConstructTypeEnum.vocab)
                .map((id) => id.lemma.toLowerCase())
                .toSet() ??
            {};
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "message": "Failed to update used vocab in ActivityChatController",
        },
      );
    }
  }

  Future<ActivitySummaryAnalyticsModel> getActivityAnalytics() async {
    final cached = ActivitySessionAnalyticsRepo.get(room.id);
    final analytics = cached?.analytics ?? ActivitySummaryAnalyticsModel();

    DateTime? timestamp = room.creationTimestamp;
    if (cached != null) {
      timestamp = cached.lastUseTimestamp;
    }

    List<OneConstructUse> uses = [];
    final analyticsService =
        MatrixState.pangeaController.matrixState.analyticsDataService;

    uses = await analyticsService.getUses(
      since: timestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
      roomId: room.id,
    );

    if (uses.isEmpty) {
      return analytics;
    }

    analytics.addConstructs(userID, uses);
    await ActivitySessionAnalyticsRepo.set(
      room.id,
      uses.first.metadata.timeStamp,
      analytics,
    );

    return analytics;
  }
}
