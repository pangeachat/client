import 'dart:async';

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
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/navigation_rail.dart';

class SpaceNavigationColumn extends StatefulWidget {
  final GoRouterState state;
  final bool showNavRail;
  const SpaceNavigationColumn({
    required this.state,
    required this.showNavRail,
    super.key,
  });

  @override
  State<SpaceNavigationColumn> createState() => SpaceNavigationColumnState();
}

class SpaceNavigationColumnState extends State<SpaceNavigationColumn> {
  bool _hovered = false;
  bool _expanded = false;
  Timer? _timer;

  void _onHoverUpdate(bool hovered) {
    if (hovered == _hovered) return;
    _hovered = hovered;
    _cancelTimer();

    if (hovered) {
      _timer = Timer(const Duration(milliseconds: 200), () {
        if (_hovered && mounted) {
          setState(() => _expanded = true);
        }
        _cancelTimer();
      });
    } else {
      setState(() => _expanded = false);
    }
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    final navRailWidth = isColumnMode
        ? FluffyThemes.navRailWidth
        : FluffyThemes.navRailWidth - 8.0;

    final double navRailExtraWidth = widget.showNavRail ? 250.0 : 0.0;
    final double columnWidth =
        isColumnMode ? FluffyThemes.columnWidth + 1.0 : 0;

    final double railWidth = widget.showNavRail ? navRailWidth + 1.0 : 0;
    final double baseWidth = columnWidth + railWidth;
    final double expandedWidth = baseWidth < navRailExtraWidth
        ? navRailExtraWidth + railWidth
        : baseWidth;

    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      width: _expanded ? expandedWidth : baseWidth,
      child: Stack(
        children: [
          if (isColumnMode)
            Positioned(
              left: navRailWidth + 1.0,
              child: SizedBox(
                height: MediaQuery.heightOf(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: const BoxDecoration(),
                      width: FluffyThemes.columnWidth,
                      child: _MainView(state: widget.state),
                    ),
                    Container(
                      width: 1.0,
                      color: theme.dividerColor,
                    ),
                  ],
                ),
              ),
            ),
          if (widget.showNavRail)
            HoverBuilder(
              builder: (context, hovered) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _onHoverUpdate(hovered);
                });

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SpacesNavigationRail(
                      activeSpaceId: widget.state.pathParameters['spaceid'],
                      path: widget.state.fullPath,
                      railWidth: _expanded
                          ? navRailWidth + navRailExtraWidth
                          : navRailWidth,
                      expanded: _expanded,
                      collapse: () {
                        _cancelTimer();
                        setState(() => _expanded = false);
                      },
                    ),
                    Container(
                      width: 1,
                      color: Theme.of(context).dividerColor,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

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
