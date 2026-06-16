import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

class AnalyticsNavigationUtil {
  static Future<void> navigateToAnalytics({
    required BuildContext context,
    ProgressIndicatorEnum? view,
    ConstructIdentifier? construct,
    String? activityRoomId,
  }) async {
    // world_v2: when a right-docked analytics panel is open (a `?right=` token
    // in the URL), drilling into an item rewrites the workspace URL instead of
    // using the old `/rooms/analytics/...` pages — vocab/grammar bloom a detail
    // card to the LEFT of the pinned summary, and a completed activity opens a
    // read-only review panel beside it. See routing.instructions.md.
    final uri = GoRouterState.of(context).uri;
    final right = parseOpenPanels(uri).right;
    final panelOpen = right.any(
      (t) => const {'analytics', 'vocab', 'grammar', 'review'}.contains(t.type),
    );
    if (panelOpen) {
      if (view == ProgressIndicatorEnum.activities) {
        if (activityRoomId != null) {
          context.go(
            WorkspaceNav.openRight(
              uri,
              PanelToken('review', shortRoomId(activityRoomId)),
              atStart: true,
            ),
          );
        }
        return;
      }
      if (construct != null &&
          {
            ProgressIndicatorEnum.wordsUsed,
            ProgressIndicatorEnum.morphsUsed,
          }.contains(view)) {
        context.go(
          WorkspaceNav.openRight(
            uri,
            PanelToken(
              view == ProgressIndicatorEnum.wordsUsed ? 'vocab' : 'grammar',
              jsonEncode(construct.toJson()),
            ),
            atStart: true,
          ),
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
