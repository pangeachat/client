import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/world/analytics_panel_controller.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

class AnalyticsNavigationUtil {
  static Future<void> navigateToAnalytics({
    required BuildContext context,
    ProgressIndicatorEnum? view,
    ConstructIdentifier? construct,
    String? activityRoomId,
  }) async {
    // world_v2: when the right-docked analytics panel is open (the top-right
    // cluster), drilling into an item uses the new layout instead of the old
    // `/rooms/analytics/...` pages — vocab/grammar open a detail card to the
    // LEFT of the pinned summary (set on [AnalyticsPanelController], not the
    // URL, so it survives navigation), and an activity opens its session chat
    // in the left zone. See world-user-cluster.instructions.md.
    if (AnalyticsPanelController.isOpen) {
      if (view == ProgressIndicatorEnum.activities) {
        if (activityRoomId != null) context.go(PRoutes.room(activityRoomId));
        return;
      }
      if (construct != null &&
          {
            ProgressIndicatorEnum.wordsUsed,
            ProgressIndicatorEnum.morphsUsed,
          }.contains(view)) {
        AnalyticsPanelController.openConstruct(
          view == ProgressIndicatorEnum.wordsUsed
              ? AnalyticsPanelTab.vocab
              : AnalyticsPanelTab.grammar,
          construct,
        );
      }
      // Other in-panel taps (no construct, level, etc.) are no-ops — the
      // cross-metric header that triggered those is hidden in the panel.
      return;
    }

    if (view == null) {
      context.go('/rooms/analytics');
      return;
    }

    if (view == ProgressIndicatorEnum.activities) {
      if (activityRoomId != null) {
        context.go('/rooms/analytics/activities/$activityRoomId');
        return;
      }
      context.go('/rooms/analytics/activities');
      return;
    }

    if (construct == null ||
        !{
          ProgressIndicatorEnum.wordsUsed,
          ProgressIndicatorEnum.morphsUsed,
        }.contains(view)) {
      context.go("/rooms/analytics/${view.route}");
      return;
    }

    final isColumnMode = FluffyThemes.isColumnMode(context);
    if (isColumnMode) {
      context.go(
        '/rooms/analytics/${view.route}/${Uri.encodeComponent(jsonEncode(construct.toJson()))}',
      );
      return;
    }

    await showAdaptiveBottomSheet(
      context: context,
      builder: (context) {
        return ConstructAnalyticsView(
          view: view.constructType,
          construct: construct,
        );
      },
    );
  }
}
