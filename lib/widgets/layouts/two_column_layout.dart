import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/routes/world/activity_detail_panel.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/widgets/layouts/mobile_course_sheet.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mobile_bottom_nav.dart';
import 'package:fluffychat/widgets/space_navigation_column.dart';

/// One persistent world-map element for the whole app shell (world_v2 map
/// architecture). The GlobalKey preserves the map's State — tiles, camera,
/// pins — even if this shell page is rebuilt or remounted across
/// navigation, so sections open *over* the map instead of refreshing it.
final GlobalKey _persistentWorldMapKey = GlobalKey(debugLabel: 'worldMap');

/// Max width of an opaque detail panel (chat, vocab, …); the map peeks in
/// the remaining canvas on wider screens (world_v2 detail contract).
const double _detailMaxWidth = 720.0;

/// Route patterns whose canvas is the transparent map hole ([EmptyPage]) in
/// column mode — the section roots and the analytics groupings. The
/// persistent map shows through and the section's content lives in the left
/// column. Matched against [GoRouterState.fullPath] (the matched *leaf*
/// pattern), so a detail route stacked under an EmptyPage parent (e.g.
/// `/rooms/:roomid` under `/rooms`) is correctly read as a detail — not the
/// map — even though go_router keeps the parent's EmptyPage page mounted.
const Set<String> _mapCanvasPaths = {
  '/',
  '/chats',
  '/rooms',
  '/courses/own',
  '/courses/browse',
  '/courses/private',
  '/courses/:spaceid',
  '/courses/:spaceid/details',
  '/analytics',
  '/analytics/morph',
  '/analytics/vocab',
  '/analytics/activities',
  '/analytics/level',
  '/settings',
  '/profile',
};

/// How the current route's canvas relates to the persistent map.
enum _CanvasMode {
  /// Paints nothing; the persistent map shows through (section roots).
  map,

  /// Opaque content capped at [_detailMaxWidth]; the map peeks alongside.
  detail,

  /// Opaque content that fills the canvas — the "Add new course" hub
  /// (`/courses`), a card floating over the persistent map.
  fullBleed,
}

_CanvasMode _canvasMode(GoRouterState state, bool isColumnMode) {
  final fullPath = state.fullPath ?? '/';
  // World is always the map; the other section roots are the map only in
  // column mode (narrow shows their content full-screen instead).
  if (fullPath == '/' || (isColumnMode && _mapCanvasPaths.contains(fullPath))) {
    return _CanvasMode.map;
  }
  // The "Add new course" hub is a card floating over the persistent map; its
  // own content absorbs taps. The activity routes (`/<uuid>` and `?activity=`)
  // are capped detail panels over the same map, not full-bleed.
  if (fullPath == '/courses') {
    return _CanvasMode.fullBleed;
  }
  return _CanvasMode.detail;
}

class TwoColumnLayout extends StatelessWidget {
  // #Pangea
  // final Widget mainView;
  final GoRouterState state;
  // Pangea#
  final Widget sideView;

  const TwoColumnLayout({
    super.key,
    // #Pangea
    // required this.mainView,
    required this.state,
    // Pangea#
    required this.sideView,
  });
  @override
  Widget build(BuildContext context) {
    // #Pangea
    // final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    bool showNavRail = isColumnMode;
    if (!showNavRail) {
      final roomID = state.pathParameters['roomid'];
      final spaceID = state.pathParameters['spaceid'];

      if (roomID == null && spaceID == null) {
        showNavRail = ![
          "newcourse",
          ":construct",
        ].any((p) => state.fullPath?.contains(p) ?? false);
      } else if (roomID == null) {
        showNavRail = state.fullPath?.endsWith(':spaceid') == true;
      }
    }

    // World is the full-bleed map: the canvas extends under where the left
    // column would be (only the rail offsets it). The "Add new course" hub
    // (`/courses`) is likewise a card floating over the full-bleed map — no
    // left column, so no divider and the map stays pannable around it.
    final showLeftColumn =
        AppSection.fromUri(state.uri) != AppSection.world &&
        state.fullPath != '/courses';
    // world_v2: the rail is vertical-left in column mode and a bottom bar
    // in narrow mode, so it only offsets the canvas in column mode.
    final columnWidth =
        (isColumnMode && showNavRail ? (FluffyThemes.navRailWidth + 1.0) : 0.0) +
        (isColumnMode && showLeftColumn
            ? (FluffyThemes.columnWidth + 1.0)
            : 0.0);
    final showBottomNav = !isColumnMode && showNavRail;
    final canvasMode = _canvasMode(state, isColumnMode);
    // The detail is capped at [_detailMaxWidth] only in column mode, where the
    // map is meant to peek alongside it. In single-column (mobile) mode there
    // is nothing alongside, so the detail fills to the column-mode breakpoint —
    // otherwise a viewport between _detailMaxWidth and the breakpoint leaves a
    // thin strip of map showing on the side (the "weird gap").
    final available = MediaQuery.sizeOf(context).width - columnWidth;
    final detailWidth = isColumnMode
        ? math.min(_detailMaxWidth, available)
        : available;
    // world_v2: `?activity=<id>` opens the activity detail in-place over the
    // persistent map — a capped detail (not full-bleed), course preserved,
    // map untouched — instead of leaving for the standalone `/<id>` page.
    final activityParam = state.uri.queryParameters['activity'];
    // The activity to center on the persistent map: the in-place `?activity=`
    // param, or the standalone `/<activityId>` route's path param.
    final focusedActivityId =
        activityParam ?? state.pathParameters['activityId'];
    final effectiveCanvasMode = activityParam != null
        ? _CanvasMode.detail
        : canvasMode;

    // Scope the persistent map to the active course (world_v2 context). A
    // joined course (`/courses/:spaceid`) scopes the map to that course's
    // content; everything else shows the whole world. Set post-frame — the
    // map listens and calls setState, which can't run during this build.
    final activeSpaceId = AppSection.activeSpaceId(state.uri);
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
        activityParam == null &&
        effectiveCanvasMode == _CanvasMode.detail;
    final canvasChild = activityParam != null
        ? ActivityDetailPanel(
            activityId: activityParam,
            parentSpaceId: activeSpaceId,
          )
        : sideView;
    // Pangea#
    return ScaffoldMessenger(
      child: Scaffold(
        // #Pangea
        bottomNavigationBar: showBottomNav
            ? MobileBottomNav(state: state)
            : null,
        // body: Row(
        body: Stack(
          fit: StackFit.expand,
          // Pangea#
          children: [
            // #Pangea
            // Persistent world map — the base layer everything overlays.
            // Built once; section pages (the transparent EmptyPage canvas)
            // and detail panels render on top of this single instance.
            Positioned.fill(
              child: WorldMap(
                key: _persistentWorldMapKey,
                // The rail + left column — and the detail panel, when one is
                // open — overlay the map; a camera-fit pads by this so the
                // selection lands centered in the exposed canvas, not behind
                // an overlay.
                leftOverlayWidth:
                    columnWidth +
                    (effectiveCanvasMode == _CanvasMode.detail &&
                            !isMobileCourse
                        ? detailWidth
                        : 0.0),
                // While an activity is shown (in-place or the standalone
                // route), center it within the exposed canvas.
                focusedActivityId: focusedActivityId,
              ),
            ),
            // The route canvas, as one stable child so the sideView Navigator
            // never remounts when the canvas mode changes (route/chat state is
            // preserved). Three modes (world_v2):
            //  • map → off the layout/hit-test tree (Offstage) so pan/zoom/tap
            //    reach the persistent map below. The sideView is go_router's
            //    nested Navigator/Overlay, which would otherwise absorb
            //    gestures even though the leaf (EmptyPage) paints nothing.
            //  • detail → capped at ~720px next to the left column, so the map
            //    peeks in the remainder on wide screens.
            //  • fullBleed → fills (the activity page hosts its own map).
            Positioned(
              left: columnWidth,
              top: 0,
              bottom: 0,
              right: effectiveCanvasMode == _CanvasMode.detail ? null : 0,
              width: effectiveCanvasMode == _CanvasMode.detail
                  ? detailWidth
                  : null,
              child: Offstage(
                offstage:
                    effectiveCanvasMode == _CanvasMode.map || isMobileCourse,
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
            SpaceNavigationColumn(state: state, showNavRail: showNavRail),
            // Container(width: 1.0, color: theme.dividerColor),
            // Expanded(child: ClipRRect(child: sideView)),
            // Pangea#
          ],
        ),
      ),
    );
  }
}
