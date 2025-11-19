import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_analytics_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityChatController {
  final String userID;
  final Future<ActivitySummaryAnalyticsModel> Function()? getAnalytics;

  ActivityChatController({
    required this.userID,
    required this.getAnalytics,
  }) {
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
        .pangeaController.getAnalytics.analyticsStream.stream
        .listen((_) {
      _updateUsedVocab();
    });
  }

  void dispose() {
    carouselController.dispose();
    _analyticsSubscription?.cancel();
    usedVocab.dispose();
    highlightedRole.dispose();
    showInstructions.dispose();
    showActivityDropdown.dispose();
    hasRainedConfetti.dispose();
    _disposed = true;
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

  void toggleShowDropdown() async {
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
    if (getAnalytics == null) return;
    final analytics = await getAnalytics!.call();
    if (!_disposed) {
      usedVocab.value = analytics.constructs[userID]
              ?.constructsOfType(ConstructTypeEnum.vocab)
              .map((id) => id.lemma.toLowerCase())
              .toSet() ??
          {};
    }
  }
}
