import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
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
    // card to the LEFT of the pinned summary, and a completed activity opens its
    // actual (locked) session chat as a left room panel beside it. See
    // routing.instructions.md.
    final uri = GoRouterState.of(context).uri;
    final panelOpen = parseOpenPanels(uri).right.any(
      (t) => const {'analytics', 'vocab', 'grammar'}.contains(t.type),
    );

    // A completed activity session is a real (locked) chat whose summary is
    // posted as a message in its own timeline (not a separate card). Open the
    // actual session as a left room panel; openExclusiveLeftRoom keeps the
    // analytics panel docked on the right (one live session).
    if (view == ProgressIndicatorEnum.activities && activityRoomId != null) {
      context.go(
        WorkspaceNav.openExclusiveLeftRoom(
          uri,
          PanelToken('room', shortRoomId(activityRoomId)),
        ),
      );
      return;
    }

    // The summary tab this metric belongs to.
    final tab = switch (view) {
      ProgressIndicatorEnum.activities => 'sessions',
      ProgressIndicatorEnum.morphsUsed => 'grammar',
      ProgressIndicatorEnum.level => 'level',
      _ => 'vocab',
    };

    // A vocab/grammar construct blooms a detail card to the LEFT of its summary
    // (atStart). With a panel already docked we add just the detail; from a cold
    // start we seat the detail and its summary together — both token writes, no
    // legacy `/rooms/analytics/...` route. See routing.instructions.md.
    if (construct != null &&
        const {
          ProgressIndicatorEnum.wordsUsed,
          ProgressIndicatorEnum.morphsUsed,
        }.contains(view)) {
      final detail = PanelToken(
        view == ProgressIndicatorEnum.wordsUsed ? 'vocab' : 'grammar',
        jsonEncode(construct.toJson()),
      );
      context.go(
        panelOpen
            ? WorkspaceNav.openExclusiveRightDetail(uri, detail)
            : WorkspaceNav.setRight(uri, [detail, PanelToken('analytics', tab)]),
      );
      return;
    }

    // A metric tap with no construct opens its summary from a cold start; when a
    // panel is already docked it is a no-op (the cross-metric header is hidden).
    if (panelOpen) return;
    context.go(WorkspaceNav.setRight(uri, [PanelToken('analytics', tab)]));
  }
}
