import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/widgets/navigation_rail.dart';
import 'matrix.dart';

/// The left chrome of the world_v2 shell: just the floating navigation rail.
/// Every section's content is now a URL-token panel rendered by the shell's
/// allocator (see [TwoColumnLayout]) — including the add-course wizard's first
/// step (the `addcourse` token). The route-driven `_MainView` left card is
/// retired, so this widget draws only the rail, in column mode (narrow screens
/// use the bottom nav). See `routing.instructions.md`.
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

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    // The vertical rail is column-mode only; narrow screens use the bottom nav.
    if (!isColumnMode || !widget.showNavRail) return const SizedBox.shrink();

    // world_v2: the rail no longer hover-expands — it stays a narrow pill that
    // floats over the map (in the shared WorkspaceDock chrome). Section/course
    // names surface via item tooltips, and joined courses also appear as tiles
    // on the add-course page, so the expand-to-show-names interaction is retired.
    // See `routing.instructions.md`.
    return SpacesNavigationRail(
      state: widget.state,
      activeSpaceId: activeSpaceIdFor(widget.state.uri),
      naviRailWidth: FluffyThemes.navRailWidth + 1.0,
      // The label section the items reserve and slide off-screen when collapsed.
      // `expanded` is always false now, so the label stays hidden; it just needs
      // room so the item's label Text isn't squeezed to a 0-width overflow.
      expandedSectionWidth: 250,
      expanded: false,
      collapse: () {},
      profile: _profile,
      onProfileUpdate: _updateProfile,
    );
  }
}
