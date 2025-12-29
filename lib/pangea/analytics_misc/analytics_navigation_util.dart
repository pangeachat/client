import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_popup.dart';
import 'package:fluffychat/pangea/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';

class AnalyticsNavigationUtil {
  static Future<void> navigateToAnalytics({
    required BuildContext context,
    ProgressIndicatorEnum? view,
    ConstructIdentifier? construct,
    String? activityRoomId,
  }) async {
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
        !{ProgressIndicatorEnum.wordsUsed, ProgressIndicatorEnum.morphsUsed}
            .contains(view)) {
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
