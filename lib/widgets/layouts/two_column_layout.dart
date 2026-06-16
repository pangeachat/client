import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/routes/world/activity_detail_panel.dart';
import 'package:fluffychat/routes/world/analytics_panel_controller.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_analytics_panel.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/widgets/layouts/mobile_course_sheet.dart';
import 'package:fluffychat/widgets/layouts/shell_layout.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mobile_bottom_nav.dart';
import 'package:fluffychat/widgets/space_navigation_column.dart';

/// One persistent world-map element for the whole app shell (world_v2 map
/// architecture). The GlobalKey preserves the map's State — tiles, camera,
/// pins — even if this shell page is rebuilt or remounted across navigation,
/// so sections open *over* the map instead of refreshing it.
final GlobalKey _persistentWorldMapKey = GlobalKey(debugLabel: 'worldMap');

/// Preserves the top-right cluster's State (counts, level, stream subs) across
/// shell rebuilds, like the persistent map — so it does not re-fetch on nav.
final GlobalKey _userClusterKey = GlobalKey(debugLabel: 'worldUserCluster');

/// All shell zone widths (detail cap, analytics card, cluster gutter, …) live in
/// [ShellLayout] — the single budget that tiles them without overlap.

/// The shell: a single persistent [WorldMap] with the active section overlaid.
/// Every routing/layout fact comes from `route_facts.dart` (the single source),
/// so this layout, the page builders in `routes.dart`, the left column, the
/// rail, and the bottom nav can't disagree. The canvas relates to the map in
/// one of three ways ([CanvasMode]): a map hole (the map shows through), a
/// capped detail panel (the map peeks alongside), or full-bleed content.
class TwoColumnLayout extends StatelessWidget {
  // #Pangea
  final GoRouterState state;
  // Pangea#
  final Widget sideView;

  const TwoColumnLayout({
    super.key,
    // #Pangea
    required this.state,
    // Pangea#
    required this.sideView,
  });

  @override
  Widget build(BuildContext context) {
    // #Pangea
    // The right-docked analytics panel is app-state ([AnalyticsPanelController]),
    // not a URL param, so the shell subscribes to it here — navigating the left
    // content (rail, a chat, a course, a map pin) never closes the panel.
    return ValueListenableBuilder<AnalyticsPanelState?>(
      valueListenable: AnalyticsPanelController.notifier,
      builder: (context, panelState, _) => _buildShell(context, panelState),
    );
    // Pangea#
  }

  // #Pangea
  Widget _buildShell(BuildContext context, AnalyticsPanelState? panelState) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final navRail = showNavRail(state, isColumnMode);
    final leftColumn = showLeftColumn(state);

    // world_v2: the rail is vertical-left in column mode and a bottom bar in
    // narrow mode, so it only offsets the canvas in column mode.
    final columnWidth =
        (isColumnMode && navRail ? (FluffyThemes.navRailWidth + 1.0) : 0.0) +
        (isColumnMode && leftColumn
            ? (FluffyThemes.columnWidth + 1.0)
            : 0.0);
    final showBottomNav = !isColumnMode && navRail;

    // The effective canvas (an open activity overlay already resolves to a
    // detail panel inside [canvasFor]).
    final canvas = canvasFor(state, isColumnMode);

    final activity = activityFor(state);
    final activeSpaceId = activeSpaceIdFor(state.uri);

    // The right-docked analytics panel (the top-right cluster's trackers), from
    // app-state. A vocab/grammar detail card blooms to the LEFT of the summary,
    // so the right zone holds two cards and is twice as wide.
    final analyticsTab = panelState?.tab;
    final analyticsConstruct = panelState?.construct;
    final analyticsDetailOpen =
        analyticsConstruct != null &&
        analyticsTab != null &&
        analyticsTab != AnalyticsPanelTab.sessions;

    // The map shows behind as a map hole (full) or — in column mode — alongside
    // a detail; this gates the cluster and the panel's tile-vs-overlay budget.
    final mapVisible =
        canvas == CanvasMode.mapHole ||
        (isColumnMode && canvas == CanvasMode.detail);

    // Single layout authority: ONE width budget tiles every floating zone (left
    // column, center detail, right panel, cluster gutter) so they can't overlap.
    // The panel hides on a full-bleed canvas (the add-course hub fills it); its
    // open-state survives in the controller, so it returns on leaving.
    final panelOpen = analyticsTab != null && canvas != CanvasMode.fullBleed;
    final layout = ShellLayout.resolve(
      viewport: MediaQuery.sizeOf(context).width,
      isColumnMode: isColumnMode,
      leftInset: columnWidth,
      canvas: canvas,
      panelOpen: panelOpen,
      panelDetailOpen: analyticsDetailOpen,
      mapVisible: mapVisible,
    );

    // Scope the persistent map to the active course (world_v2 context). A joined
    // course scopes the map to that course's content; everything else shows the
    // whole world. Set post-frame — the map listens and calls setState, which
    // can't run during this build.
    final coursePlanId = activeSpaceId == null
        ? null
        : Matrix.of(context).client.getRoomById(activeSpaceId)?.coursePlan?.uuid;
    final MapContext mapContext = coursePlanId == null
        ? const WorldMapContext()
        : CourseMapContext(coursePlanId);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => MapContextController.set(mapContext),
    );

    // world_v2 mobile: a joined course on a narrow screen rides in a draggable
    // bottom sheet over the persistent (course-scoped) map instead of a
    // full-screen panel that hides it. The detail (sideView) moves into the
    // sheet; the map shows above the sheet's peek.
    final isMobileCourse =
        !isColumnMode &&
        activeSpaceId != null &&
        activity == null &&
        canvas == CanvasMode.detail;

    // `?activity=<id>` opens the activity detail in-place over the persistent
    // map — a capped detail (not full-bleed), course preserved, map untouched.
    final canvasChild = activity != null
        ? ActivityDetailPanel(
            activityId: activity.id,
            parentSpaceId: activeSpaceId,
            roomId: activity.roomId,
            launch: activity.launch,
          )
        : sideView;
    // Pangea#
    return ScaffoldMessenger(
      child: Scaffold(
        // #Pangea
        bottomNavigationBar: showBottomNav
            ? MobileBottomNav(state: state)
            : null,
        body: Stack(
          fit: StackFit.expand,
          // Pangea#
          children: [
            // #Pangea
            // Persistent world map — the base layer everything overlays. Built
            // once; section pages (the transparent EmptyPage canvas) and detail
            // panels render on top of this single instance.
            Positioned.fill(
              child: WorldMap(
                key: _persistentWorldMapKey,
                // The overlays (rail + column + detail on the left, the docked
                // panel on the right) pad the camera so a course fit lands in the
                // exposed area — both insets come from the one layout budget.
                leftOverlayWidth: layout.mapLeftOverlay,
                rightOverlayWidth: layout.mapRightOverlay,
                // What the map brings into the exposed canvas (today: the open
                // activity). Extend via a new [MapFocus] kind in route_facts.
                focus: mapFocusFor(state),
              ),
            ),
            // The route canvas, as one stable child so the sideView Navigator
            // never remounts when the canvas mode changes. Three modes:
            //  • mapHole → off the hit-test tree (Offstage) so pan/zoom/tap
            //    reach the persistent map below.
            //  • detail → capped at ~720px next to the left column, map peeks.
            //  • fullBleed → fills (the activity page hosts its own map).
            Positioned(
              left: columnWidth,
              top: 0,
              bottom: 0,
              right: canvas == CanvasMode.detail ? null : 0,
              // Bounded by the layout budget so it can never slide under the
              // docked panel; the map peeks beyond it.
              width: canvas == CanvasMode.detail ? layout.detailWidth : null,
              child: Offstage(
                offstage: canvas == CanvasMode.mapHole || isMobileCourse,
                child: ClipRRect(
                  child: isMobileCourse
                      ? const SizedBox.shrink()
                      : canvasChild,
                ),
              ),
            ),
            // world_v2 mobile course: the detail rides a draggable sheet over
            // the course-scoped persistent map (peek = handle + title + tabs).
            if (isMobileCourse)
              Positioned.fill(child: MobileCourseSheet(child: canvasChild)),
            SpaceNavigationColumn(state: state, showNavRail: navRail),
            // The right-docked analytics panel, opened by the top-right cluster
            // (app-state). Sized by [ShellLayout]: a docked card that tiles
            // beside the content (cluster in the gutter), or a full-bleed
            // Slide-Over when there's no room / on narrow — so it can never
            // accidentally overlap the detail.
            if (analyticsTab != null &&
                layout.analyticsMode != AnalyticsPanelMode.none)
              Positioned(
                top: 0,
                bottom: 0,
                left: layout.analyticsMode == AnalyticsPanelMode.fullBleed
                    ? layout.leftInset
                    : null,
                right: layout.analyticsMode == AnalyticsPanelMode.dockedCard
                    ? ShellLayout.clusterGutter
                    : 0,
                width: layout.analyticsMode == AnalyticsPanelMode.dockedCard
                    ? layout.analyticsZoneWidth
                    : null,
                child: WorldAnalyticsPanel(
                  tab: analyticsTab,
                  construct: analyticsConstruct,
                  fullBleed:
                      layout.analyticsMode == AnalyticsPanelMode.fullBleed,
                ),
              ),
            // The persistent top-right user cluster — painted last so it sits in
            // the gutter beside the panel (Figma). Hidden behind a full-bleed
            // panel; shown only where the map is the backdrop.
            if (layout.clusterVisible)
              Positioned(
                top: 12 + MediaQuery.viewPaddingOf(context).top,
                right: 12 + MediaQuery.viewPaddingOf(context).right,
                child: WorldUserCluster(key: _userClusterKey),
              ),
            // Pangea#
          ],
        ),
      ),
    );
  }
}
