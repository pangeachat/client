import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';
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

    // While a section has a live practice session, its analytics summary and
    // construct details are off-limits (no peeking at definitions
    // mid-exercise) — the tap resumes the session instead. See
    // routing.instructions.md § Practice is a persistent background session.
    if (const {
      ProgressIndicatorEnum.wordsUsed,
      ProgressIndicatorEnum.morphsUsed,
    }.contains(view)) {
      final constructType = view!.constructType;
      if (PracticeSessionHolder.instance.blocksAnalytics(constructType)) {
        context.go(WorkspaceNav.openPractice(uri, constructType));
        return;
      }
    }

    final panelOpen = parseOpenPanels(
      uri,
    ).right.any((t) => t.type.isNonPracticeAnalyticsPanel);

    // A completed activity session is a real (locked) chat whose summary is
    // posted as a message in its own timeline (not a separate card). Open the
    // actual session as a left `session` panel: it shares the single detail slot
    // with the right-column vocab/grammar details, so opening it closes any open
    // construct detail (one detail at a time across columns). See
    // routing.instructions.md.
    if (view == ProgressIndicatorEnum.activities && activityRoomId != null) {
      context.go(WorkspaceNav.openExclusiveSession(uri, activityRoomId));
      return;
    }

    // A vocab/grammar construct blooms a detail card to the LEFT of its summary.
    // `openConstructDetail` is the single detail slot: it replaces any open
    // vocab/grammar detail AND closes an open activity-`session` review (one
    // detail at a time across columns), seating the summary too on a cold start.
    // See routing.instructions.md.
    if (construct != null &&
        const {
          ProgressIndicatorEnum.wordsUsed,
          ProgressIndicatorEnum.morphsUsed,
        }.contains(view)) {
      context.go(
        WorkspaceNav.openConstructDetail(
          uri,
          view!.constructType,
          constructId: construct,
        ),
      );
      return;
    }

    // A metric tap with no construct opens its summary from a cold start; when a
    // panel is already docked it is a no-op (the cross-metric header is hidden).
    if (panelOpen) return;
    context.go(WorkspaceNav.openAnalytics(uri, subpage: view));
  }
}
