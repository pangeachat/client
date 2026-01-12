import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/spaces/space_navigation_column.dart';

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
        showNavRail = !["newcourse", ":construct"].any(
          (p) => state.fullPath?.contains(p) ?? false,
        );
      } else if (roomID == null) {
        showNavRail = state.fullPath?.endsWith(':spaceid') == true;
      }
    }

    final columnWidth =
        (showNavRail ? (FluffyThemes.navRailWidth + 1.0) : 0.0) +
            (isColumnMode ? (FluffyThemes.columnWidth + 1.0) : 0.0);
    // Pangea#
    return ScaffoldMessenger(
      child: Scaffold(
        // #Pangea
        // body: Row(
        body: Stack(
          fit: StackFit.expand,
          // Pangea#
          children: [
            // #Pangea
            Positioned.fill(
              left: columnWidth,
              child: ClipRRect(child: sideView),
            ),
            SpaceNavigationColumn(
              state: state,
              showNavRail: showNavRail,
            ),
            // Container(
            //   clipBehavior: Clip.antiAlias,
            //   decoration: const BoxDecoration(),
            //   width: FluffyThemes.columnWidth + FluffyThemes.navRailWidth,
            //   child: mainView,
            // ),
            // Container(width: 1.0, color: theme.dividerColor),
            // Expanded(child: ClipRRect(child: sideView)),
            // Pangea#
          ],
        ),
      ),
    );
  }
}
