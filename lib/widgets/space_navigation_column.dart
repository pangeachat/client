import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/analytics/level/level_analytics_details_content.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/routes/courses/find_course_page.dart';
import 'package:fluffychat/routes/settings/settings.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/navigation_rail.dart';
import 'matrix.dart';

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
  Profile? _profile;

  @override
  void initState() {
    super.initState();
    Matrix.of(context).client.fetchOwnProfile().then((profile) {
      if (mounted) {
        setState(() {
          _profile = profile;
        });
      }
    });
  }

  void _updateProfile(Profile profile) {
    if (mounted) {
      setState(() {
        _profile = profile;
      });
    }
  }

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
    // World is the full-bleed map: no left column. Every other section
    // overlays its list/detail card over the map in the left column.
    final showLeftColumn =
        AppSection.fromUri(widget.state.uri) != AppSection.world;

    // width of base navigation rail, if visible
    final baseNaviRailWidth = isColumnMode
        ? FluffyThemes.navRailWidth
        : FluffyThemes.navRailWidth - 8.0;

    // width of the real navigation rail, accounting for pages where not visible
    final double realNaviRailWidth = widget.showNavRail
        ? baseNaviRailWidth + 1.0
        : 0;

    // width of the expanded section of the navigation column, if visible
    final baseExpandedNaviWidth = 250.0;

    // width of the real expanded section, accounting for pages where not visible
    final realExpandedNaviWidth = widget.showNavRail
        ? baseExpandedNaviWidth
        : 0.0;

    return Stack(
      children: [
        if (isColumnMode && showLeftColumn)
          Positioned.fill(
            left: realNaviRailWidth,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(),
                  width: FluffyThemes.columnWidth,
                  child: _MainView(state: widget.state),
                ),
                Container(width: 1.0, color: theme.dividerColor),
              ],
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
                    naviRailWidth: realNaviRailWidth,
                    expandedSectionWidth: realExpandedNaviWidth,
                    expanded: _expanded,
                    collapse: () {
                      _cancelTimer();
                      setState(() => _expanded = false);
                    },
                    profile: _profile,
                    onProfileUpdate: _updateProfile,
                  ),
                  Container(width: 1, color: Theme.of(context).dividerColor),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _MainView extends StatelessWidget {
  final GoRouterState state;

  const _MainView({required this.state});

  @override
  Widget build(BuildContext context) {
    // world_v2: the left column is decided by the active section (exact
    // path segments via AppSection), with sub-views chosen by segment
    // inspection — never substring matching on the full path.
    final uri = state.uri;
    final segments = uri.pathSegments;
    final section = AppSection.fromUri(uri);

    switch (section) {
      case AppSection.analytics:
        final sub = segments.length > 1 ? segments[1] : null;
        final practice = segments.contains('practice');
        if (sub == 'level') return const LevelAnalyticsDetailsContent();
        if (sub == 'activities') return const ActivityArchive();
        if (sub == ConstructTypeEnum.morph.string) {
          return ConstructAnalyticsView(
            view: ConstructTypeEnum.morph,
            showPracticeButton: !practice,
          );
        }
        return ConstructAnalyticsView(
          view: ConstructTypeEnum.vocab,
          showPracticeButton: !practice,
        );

      // Avatar surface (world_v2): profile + settings share the merged
      // menu in the left column. /profile/edit shows the editor in the
      // canvas while this menu stays in the column.
      case AppSection.settings:
      case AppSection.profile:
        return Settings(key: state.pageKey);

      case AppSection.courses:
        // Find/browse flows show the course list in the left column.
        final spaceId = AppSection.activeSpaceId(uri);
        if (spaceId == null && !segments.contains('addcourse')) {
          return const FindCoursePage();
        }
        // Inside a specific course chat, keep the chat list in the column.
        final roomId = state.pathParameters['roomid'];
        final space = spaceId != null
            ? Matrix.of(context).client.getRoomById(spaceId)
            : null;
        if (roomId != null || space == null) {
          return ChatList(activeChat: roomId, activeSpace: spaceId);
        }
        // A joined course root: the location-grouped objective outline
        // (world_v2). The course detail/chat canvas relayout is its own
        // design pass (world_v2 open decision: course root layout).
        return CourseObjectivesView(space: space);

      case AppSection.world:
        // The world map is the full-bleed canvas; no left column. (The
        // column is skipped by SpaceNavigationColumn for this section.)
        return const SizedBox.shrink();

      case AppSection.chats:
        return ChatList(
          activeChat: state.pathParameters['roomid'],
          activeSpace: state.pathParameters['spaceid'],
        );
    }
  }
}
