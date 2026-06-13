import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/routes/world/world_map.dart';
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
              child: ClipRRect(child: sideView),
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
