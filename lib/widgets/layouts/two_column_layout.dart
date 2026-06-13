import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/widgets/layouts/map_canvas_scope.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mobile_bottom_nav.dart';
import 'package:fluffychat/widgets/space_navigation_column.dart';

/// One persistent world-map element for the whole app shell (world_v2 map
/// architecture). The GlobalKey preserves the map's State — tiles, camera,
/// pins — even if this shell page is rebuilt or remounted across
/// navigation, so sections open *over* the map instead of refreshing it.
final GlobalKey _persistentWorldMapKey = GlobalKey(debugLabel: 'worldMap');

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
    // column would be (only the rail offsets it).
    final showLeftColumn =
        AppSection.fromUri(state.uri) != AppSection.world;
    // world_v2: the rail is vertical-left in column mode and a bottom bar
    // in narrow mode, so it only offsets the canvas in column mode.
    final columnWidth =
        (isColumnMode && showNavRail ? (FluffyThemes.navRailWidth + 1.0) : 0.0) +
        (isColumnMode && showLeftColumn
            ? (FluffyThemes.columnWidth + 1.0)
            : 0.0);
    final showBottomNav = !isColumnMode && showNavRail;

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
            Positioned.fill(child: WorldMap(key: _persistentWorldMapKey)),
            Positioned.fill(
              left: columnWidth,
              // When the canvas is the transparent map hole (EmptyPage), the
              // sideView is go_router's nested Navigator/Overlay — which
              // absorbs pointer events even when its leaf is transparent.
              // Take it fully off the layout/hit-test tree so pan/zoom/tap
              // reach the map below; opaque detail pages stay onstage and
              // cover the map. The Navigator's route state is preserved.
              child: ValueListenableBuilder<int>(
                valueListenable: MapCanvasScope.listenable,
                builder: (context, mapCanvasCount, child) => Offstage(
                  offstage: mapCanvasCount > 0,
                  child: child,
                ),
                child: ClipRRect(child: sideView),
              ),
            ),
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
