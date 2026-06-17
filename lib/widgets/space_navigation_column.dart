import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
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
    final isColumnMode = FluffyThemes.isColumnMode(context);
    // The vertical rail is column-mode only; narrow screens use the bottom nav.
    if (!isColumnMode || !widget.showNavRail) return const SizedBox.shrink();

    final realNaviRailWidth = FluffyThemes.navRailWidth + 1.0;
    const realExpandedNaviWidth = 250.0;

    return HoverBuilder(
      builder: (context, hovered) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _onHoverUpdate(hovered);
        });

        // The rail floats as a content-height bar over the map, matching the
        // card panels (no full-height divider).
        return SpacesNavigationRail(
          state: widget.state,
          activeSpaceId: activeSpaceIdFor(widget.state.uri),
          naviRailWidth: realNaviRailWidth,
          expandedSectionWidth: realExpandedNaviWidth,
          expanded: _expanded,
          collapse: () {
            _cancelTimer();
            setState(() => _expanded = false);
          },
          profile: _profile,
          onProfileUpdate: _updateProfile,
        );
      },
    );
  }
}
