import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';

/// InkWell-backed tap target with a gold ring painted while focused (#7219):
/// focusable and Enter/Space-activatable where a bare GestureDetector is not.
/// InkWell's own focus highlight is no indicator here — an opaque fill
/// swallows it, and on a clear or lightly washed control it measures 1.3 to
/// 1.5:1 (#8880) — so the ring replaces it. Worn by the top-right cluster's avatar,
/// stat trackers and language flag, and (via [NaviRailItem.focusRingShape])
/// the nav rail's course avatars (#8724).
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
      BorderSide(color: Theme.of(context).pangea.goldGraphic, width: ringWidth);

  /// The same ring as a [ButtonStyle.side], for a control that is already a
  /// Material button (the map's zoom controls, #8880): wrapping one in this
  /// widget would nest a second focusable and cost a dead Tab stop. Gated on
  /// [highlightsEnabled] here too, because [WidgetState.focused] is set
  /// whether or not Material would show a focus highlight.
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

  /// Passed through to the InkWell.
  final ValueChanged<bool>? onHover;
  final Color? hoverColor;

  /// Where the ring sits on [shape]'s edge, as [BorderSide.strokeAlign].
  /// Inside by default; outside for a control whose own fill can match the
  /// ring's luminance, so focus repaints the surface around the fill rather
  /// than the fill itself.
  final double ringStrokeAlign;

  const FocusRingTapTarget({
    required this.onTap,
    required this.shape,
    required this.child,
    this.label,
    this.focusNode,
    this.onHover,
    this.hoverColor,
    this.ringStrokeAlign = BorderSide.strokeAlignInside,
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
      onHover: widget.onHover,
      hoverColor: widget.hoverColor,
      // The ring is the indicator. The wash would only darken the field just
      // inside it, below 3:1 on a lit tracker (#8880).
      focusColor: Colors.transparent,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: widget.shape.copyWith(
            side: showRing
                ? FocusRingTapTarget.ringSide(
                    context,
                  ).copyWith(strokeAlign: widget.ringStrokeAlign)
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
