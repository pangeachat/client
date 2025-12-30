import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_popup.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_page/activity_archive.dart';
import 'package:fluffychat/pangea/analytics_summary/level_analytics_details_content.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/widgets/navigation_rail.dart';

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
    final theme = Theme.of(context);

    // #Pangea
    bool showNavRail = FluffyThemes.isColumnMode(context);
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
    // Pangea#

    return ScaffoldMessenger(
      child: Scaffold(
        body: Row(
          children: [
            // #Pangea
            if (showNavRail) ...[
              SpacesNavigationRail(
                activeSpaceId: state.pathParameters['spaceid'],
                path: state.fullPath,
              ),
              Container(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ],
            if (FluffyThemes.isColumnMode(context)) ...[
              // Pangea#
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(),
                // #Pangea
                // width: FluffyThemes.columnWidth + FluffyThemes.navRailWidth,
                // child: mainView,
                width: FluffyThemes.columnWidth,
                child: _MainView(state: state),
                // Pangea#
              ),
              Container(
                width: 1.0,
                color: theme.dividerColor,
              ),
              // Pangea#
            ],
            // Pangea#
            Expanded(
              child: ClipRRect(
                child: sideView,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// #Pangea
class _MainView extends StatelessWidget {
  final GoRouterState state;

  const _MainView({
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final path = state.fullPath;
    if (path == null) {
      return ChatList(
        activeChat: state.pathParameters['roomid'],
        activeSpaceId: state.pathParameters['spaceid'],
      );
    }

    if (path.contains("analytics")) {
      if (path.contains("analytics/level")) {
        return const LevelAnalyticsDetailsContent();
      } else if (path.contains("analytics/activities")) {
        return const ActivityArchive();
      } else if (path.contains("analytics/${ConstructTypeEnum.morph.string}")) {
        return const ConstructAnalyticsView(view: ConstructTypeEnum.morph);
      }
      return const ConstructAnalyticsView(view: ConstructTypeEnum.vocab);
    }

    if (path.contains("settings")) {
      return Settings(key: state.pageKey);
    }

    if (path.contains('course')) {
      return Center(
        child: SizedBox(
          width: 250.0,
          child: CachedNetworkImage(
            imageUrl:
                "${AppConfig.assetsBaseURL}/${SpaceConstants.sideBearFileName}",
            errorWidget: (context, url, error) => const SizedBox(),
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator.adaptive(),
            ),
          ),
        ),
      );
    }

    return ChatList(
      activeChat: state.pathParameters['roomid'],
      activeSpaceId: state.pathParameters['spaceid'],
    );
  }
}
// Pangea#
