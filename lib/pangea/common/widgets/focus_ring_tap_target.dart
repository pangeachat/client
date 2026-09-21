import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

/// InkWell-backed tap target for opaque-filled controls (#7219): focusable and
/// Enter/Space-activatable where a bare GestureDetector is not, with a gold
/// ring painted while focused — an opaque fill swallows InkWell's
/// behind-the-child focus highlight, so these need an explicit ring. Worn by
/// the top-right cluster's avatar and language flag, and (via
/// [NaviRailItem.focusRingShape]) the nav rail's course avatars (#8724).
///
/// The ring paints in the FOREGROUND: a background decoration is painted
/// before the child, so an opaque child swallows the stroke down to a
/// near-invisible sliver — the very failure this widget exists to fix
/// (#8724 review).
///
/// The ring is a keyboard affordance, not decoration: it renders only while
/// [FocusManager.highlightMode] is traditional — the same gate Material's own
/// focus highlights use — so touch users never see it, and pointer clicks
/// (which don't move Flutter focus) don't summon it (#8724 review).
class FocusRingTapTarget extends StatefulWidget {
  /// One ring look for every explicit focus ring (also the filter pills' ring
  /// in world_map_filter_bar.dart): thin enough to sit quietly on the chrome,
  /// still unmissable while tabbing.
  static const double ringWidth = 2.0;

  static BorderSide ringSide(BuildContext context) =>
      BorderSide(color: AppConfig.goldByTheme(context), width: ringWidth);

  /// Whether explicit focus rings should render at all right now — Flutter's
  /// gate for Material focus highlights: traditional (keyboard-driven) yes,
  /// touch no.
  static bool get highlightsEnabled =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  final VoidCallback onTap;
  final OutlinedBorder shape;
  final Widget child;

  /// Optional external focus node for the InkWell — for callers that need to
  /// hand the node elsewhere too (the filter pill gives its node to
  /// [MenuAnchor.childFocusNode] so a closing menu returns focus here).
  final FocusNode? focusNode;

  const FocusRingTapTarget({
    required this.onTap,
    required this.shape,
    required this.child,
    this.focusNode,
    super.key,
  });

  @override
  State<FocusRingTapTarget> createState() => _FocusRingTapTargetState();
}

class _FocusRingTapTargetState extends State<FocusRingTapTarget> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final showRing = _focused && FocusRingTapTarget.highlightsEnabled;
    return InkWell(
      onTap: widget.onTap,
      focusNode: widget.focusNode,
      customBorder: widget.shape,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: widget.shape.copyWith(
            side: showRing
                ? FocusRingTapTarget.ringSide(context)
                : BorderSide.none,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
