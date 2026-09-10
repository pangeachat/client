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

  /// [AppConfig.goldMarkByTheme], not the decorative [AppConfig.goldByTheme]:
  /// an indicator is a graphic the user has to read, so 1.4.11 wants 3:1 of it
  /// against what it sits on, and the light theme's gold managed 1.58:1 on the
  /// map surface and 1.43:1 on the cluster's `surfaceContainer` (#8880). Every
  /// ring in the app is this one colour — the trackers' ring has to match the
  /// avatar's beside it — so the deepening lands here rather than per-caller.
  static BorderSide ringSide(BuildContext context) =>
      BorderSide(color: AppConfig.goldMarkByTheme(context), width: ringWidth);

  /// The same ring as a Material [ButtonStyle] side, for a control that is
  /// **already** a button — the map's zoom [IconButton]s (#8880). Wrapping one
  /// in a [FocusRingTapTarget] would nest a second focusable inside it and cost
  /// a dead Tab stop, so those keep their own button and take the ring through
  /// its style instead.
  ///
  /// The [highlightsEnabled] gate is applied here for the same reason the
  /// widget applies it: [WidgetState.focused] is set whenever the button holds
  /// focus, whether or not Material would show a focus highlight, so without
  /// the gate a touch user would see the ring.
  static WidgetStateProperty<BorderSide> ringSideProperty(
    BuildContext context,
  ) => WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused) && highlightsEnabled
        ? ringSide(context)
        : BorderSide.none,
  );

  /// Whether explicit focus rings should render at all right now — Flutter's
  /// gate for Material focus highlights: traditional (keyboard-driven) yes,
  /// touch no.
  static bool get highlightsEnabled =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  final VoidCallback onTap;
  final OutlinedBorder shape;
  final Widget child;

  /// The control's accessible name. When set, the target announces as one
  /// button named [label] — name, role, focus and tap on a single semantics
  /// node — and [child] is hidden from assistive tech. Do not name the target
  /// from outside instead: a `Semantics(excludeSemantics: true)` around it
  /// drops the InkWell's focus semantics (a named button no screen reader can
  /// Tab to), and an `onTap` on an outer Semantics splits the tap onto a
  /// second, nameless focusable node (#8873).
  final String? label;

  /// Optional external focus node for the InkWell — for callers that need to
  /// hand the node elsewhere too (the filter pill gives its node to
  /// [MenuAnchor.childFocusNode] so a closing menu returns focus here).
  final FocusNode? focusNode;

  const FocusRingTapTarget({
    required this.onTap,
    required this.shape,
    required this.child,
    this.label,
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
    final label = widget.label;
    final target = InkWell(
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
        child: label == null
            ? widget.child
            : ExcludeSemantics(child: widget.child),
      ),
    );
    if (label == null) return target;
    return Semantics(button: true, label: label, child: target);
  }
}
