import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

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
    // Pangea#
    return ScaffoldMessenger(
      child: Scaffold(
        body: Row(
          children: [
            // #Pangea
            SpaceNavigationColumn(state: state),
            // Container(
            //   clipBehavior: Clip.antiAlias,
            //   decoration: const BoxDecoration(),
            //   width: FluffyThemes.columnWidth + FluffyThemes.navRailWidth,
            //   child: mainView,
            // ),
            // Container(width: 1.0, color: theme.dividerColor),
            // Pangea#
            Expanded(child: ClipRRect(child: sideView)),
          ],
        ),
      ),
    );
  }
}
