import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/routes/world/activity_detail_panel.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/widgets/layouts/mobile_course_sheet.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mobile_bottom_nav.dart';
import 'package:fluffychat/widgets/space_navigation_column.dart';

/// One persistent world-map element for the whole app shell (world_v2 map
/// architecture). The GlobalKey preserves the map's State — tiles, camera,
/// pins — even if this shell page is rebuilt or remounted across navigation,
/// so sections open *over* the map instead of refreshing it.
final GlobalKey _persistentWorldMapKey = GlobalKey(debugLabel: 'worldMap');

/// Max width of an opaque detail panel (chat, vocab, …); the map peeks in the
/// remaining canvas on wider screens (world_v2 detail contract).
const double _detailMaxWidth = 720.0;

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

    // The detail is capped at [_detailMaxWidth] only in column mode, where the
    // map is meant to peek alongside it. In single-column (mobile) mode there is
    // nothing alongside, so the detail fills to the column-mode breakpoint —
    // otherwise a viewport between _detailMaxWidth and the breakpoint leaves a
    // thin strip of map showing on the side (the "weird gap").
    final available = MediaQuery.sizeOf(context).width - columnWidth;
    final detailWidth = isColumnMode
        ? math.min(_detailMaxWidth, available)
        : available;

    final activity = activityFor(state);
    final activeSpaceId = activeSpaceIdFor(state);

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
                // The rail + left column — and the detail panel, when one is
                // open — overlay the map; a camera-fit pads by this so the
                // selection lands centered in the exposed canvas.
                leftOverlayWidth:
                    columnWidth +
                    (canvas == CanvasMode.detail && !isMobileCourse
                        ? detailWidth
                        : 0.0),
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
            // world_v2 mobile course: the detail rides a draggable sheet over
            // the course-scoped persistent map (peek = handle + title + tabs).
            if (isMobileCourse)
              Positioned.fill(child: MobileCourseSheet(child: canvasChild)),
            SpaceNavigationColumn(state: state, showNavRail: navRail),
            // Pangea#
          ],
        ),
      ),
    );
  }
}
