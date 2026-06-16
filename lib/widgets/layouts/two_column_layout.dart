import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/routes/world/activity_detail_panel.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/workspace_right_panel.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/widgets/layouts/mobile_course_sheet.dart';
import 'package:fluffychat/widgets/layouts/panel_allocator.dart';
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

/// The shell: a single persistent [WorldMap] with the active section overlaid.
/// Every routing/layout fact comes from `route_facts.dart` (the single source).
/// Right-column panels (analytics, a vocab/grammar detail, a completed-activity
/// review) are named by the URL's `?right=` list and positioned by
/// [PanelAllocator] — one shared width budget so panels and the route-driven
/// center detail tile without overlap. The left column + center detail are
/// still route-driven and fed in as the fixed left inset. See
/// `routing.instructions.md`.
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
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final navRail = showNavRail(state, isColumnMode);
    final leftColumn = showLeftColumn(state);

    // world_v2: the rail is vertical-left in column mode and a bottom bar in
    // narrow mode, so it only offsets the canvas in column mode. This route-
    // driven left inset is fed to the allocator as fixed chrome until the left
    // column is itself URL-driven.
    final columnWidth =
        (isColumnMode && navRail ? (FluffyThemes.navRailWidth + 1.0) : 0.0) +
        (isColumnMode && leftColumn ? (FluffyThemes.columnWidth + 1.0) : 0.0);
    final showBottomNav = !isColumnMode && navRail;

    // The effective canvas (an open activity overlay already resolves to a
    // detail panel inside [canvasFor]).
    final canvas = canvasFor(state, isColumnMode);
    final activity = activityFor(state);
    final activeSpaceId = activeSpaceIdFor(state.uri);

    final viewport = MediaQuery.sizeOf(context).width;

    // Right-column panels from the URL — the single source of truth for what's
    // open. Every token parsed here has a valid right-column def (the parser
    // dropped unknown/wrong-column tokens), so the lookup is non-null.
    final rightTokens = parseOpenPanels(state.uri).right;
    final rightDefs = [
      for (final token in rightTokens) PanelRegistry.defFor(token.type)!,
    ];
    final layout = PanelAllocator.allocate(
      viewport: viewport,
      isColumnMode: isColumnMode,
      left: const [],
      right: rightDefs,
      railWidth: columnWidth,
    );

    // The map shows behind as a map hole (full) or — in column mode — alongside
    // a detail; this gates the cluster.
    final mapVisible =
        canvas == CanvasMode.mapHole ||
        (isColumnMode && canvas == CanvasMode.detail);

    // Bound the route-driven center detail by the right-covered width so it can
    // never slide under a right panel (the non-overlap guarantee).
    final detailWidth = canvas == CanvasMode.detail
        ? math.min(
            ShellLayout.detailMax,
            math.max(0.0, viewport - columnWidth - layout.mapRightOverlay),
          )
        : null;
    final mapLeftOverlay =
        columnWidth + (canvas == CanvasMode.detail ? (detailWidth ?? 0.0) : 0.0);

    // Scope the persistent map to the active course (world_v2 context). Set
    // post-frame — the map listens and calls setState, which can't run now.
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
    // bottom sheet over the persistent (course-scoped) map.
    final isMobileCourse =
        !isColumnMode &&
        activeSpaceId != null &&
        activity == null &&
        canvas == CanvasMode.detail;

    // `?activity=<id>` opens the activity detail in-place over the map.
    final canvasChild = activity != null
        ? ActivityDetailPanel(
            activityId: activity.id,
            parentSpaceId: activeSpaceId,
            roomId: activity.roomId,
            launch: activity.launch,
          )
        : sideView;

    return ScaffoldMessenger(
      child: Scaffold(
        bottomNavigationBar: showBottomNav
            ? MobileBottomNav(state: state)
            : null,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Persistent world map — the base layer everything overlays.
            Positioned.fill(
              child: WorldMap(
                key: _persistentWorldMapKey,
                // Overlays pad the camera so a course fit lands in the exposed
                // area: left = rail + column + detail; right = the panel zone.
                leftOverlayWidth: mapLeftOverlay,
                rightOverlayWidth: layout.mapRightOverlay,
                focus: mapFocusFor(state),
              ),
            ),
            // The route canvas, as one stable child so the sideView Navigator
            // never remounts when the canvas mode changes:
            //  • mapHole → Offstage so pan/zoom/tap reach the map below.
            //  • detail → capped, bounded by the right panel zone; map peeks.
            //  • fullBleed → fills (the activity page hosts its own map).
            Positioned(
              left: columnWidth,
              top: 0,
              bottom: 0,
              right: canvas == CanvasMode.detail ? null : 0,
              width: canvas == CanvasMode.detail ? detailWidth : null,
              child: Offstage(
                offstage: canvas == CanvasMode.mapHole || isMobileCourse,
                child: ClipRRect(
                  child: isMobileCourse
                      ? const SizedBox.shrink()
                      : canvasChild,
                ),
              ),
            ),
            if (isMobileCourse)
              Positioned.fill(child: MobileCourseSheet(child: canvasChild)),
            SpaceNavigationColumn(state: state, showNavRail: navRail),
            // Right-column panels (analytics summary, a vocab/grammar detail, a
            // completed-activity review) from `?right=`, each placed at its
            // allocator slot. The slots tile and never overlap by construction;
            // a collapsed slot renders as a peek the user can tap to re-expand.
            for (var i = 0; i < rightTokens.length; i++)
              if (layout.right[i].vis != PanelVis.hidden)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: layout.right[i].left,
                  width: layout.right[i].width,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: WorkspaceRightPanel(
                      token: rightTokens[i],
                      currentUri: state.uri,
                      peek: layout.right[i].vis == PanelVis.peek,
                    ),
                  ),
                ),
            // The persistent top-right user cluster — the right column's entry
            // point. It sits in the gutter the allocator reserves beside the
            // panels; hidden on a full-bleed canvas or behind a narrow panel.
            if (mapVisible && layout.clusterVisible)
              Positioned(
                top: 12 + MediaQuery.viewPaddingOf(context).top,
                right: 12 + MediaQuery.viewPaddingOf(context).right,
                child: WorldUserCluster(key: _userClusterKey),
              ),
          ],
        ),
      ),
    );
  }
}
