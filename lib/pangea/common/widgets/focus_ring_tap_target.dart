import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';

/// InkWell-backed tap target with a gold ring painted while focused (#7219):
/// focusable and Enter/Space-activatable where a bare GestureDetector is not.
/// InkWell's own focus highlight is no indicator here — an opaque fill
/// swallows it, and on a clear or lightly washed control it measures 1.3 to
/// 1.5:1 (#8880) — so the ring replaces it. Worn by the top-right cluster's avatar,
/// stat trackers and language flag, and (via [NaviRailItem.focusRingShape])
/// the nav rail's course avatars (#8724); the level badges, which overhang the
/// XP ring and the map, wear the two-tone ring instead ([twoToneRing]).
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

  /// The two-tone ring's pair, light on the mark's side and dark beyond it —
  /// also the map pins' ring (PinSemanticsLayer). Deliberately not theme
  /// tokens: over map tiles or the XP ring no single colour holds 3:1, while
  /// this pair measures over 9:1 against each other on any backdrop, so one
  /// of the two always clears 3:1 against whatever is behind it (#9114).
  static const Color twoToneInner = Colors.white;
  static const Color twoToneOuter = Color(0xDD000000);

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

  /// Paint the [twoToneInner] / [twoToneOuter] pair instead of the gold ring:
  /// two bands of [ringWidth] on the [ringStrokeAlign] side of [shape]'s edge,
  /// the light one toward the control and the dark one toward its
  /// surroundings. For a control whose ring crosses map tiles or the XP ring:
  /// the level medal and the narrow bar's level badge (#9114).
  final bool twoToneRing;

  const FocusRingTapTarget({
    required this.onTap,
    required this.shape,
    required this.child,
    this.label,
    this.focusNode,
    this.onHover,
    this.hoverColor,
    this.ringStrokeAlign = BorderSide.strokeAlignInside,
    this.twoToneRing = false,
    super.key,
  }) : assert(
         !twoToneRing || ringStrokeAlign != BorderSide.strokeAlignCenter,
         'a two-tone ring sits on one side of the edge',
       );

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
      child: FocusRing(
        shape: widget.shape,
        show: showRing,
        strokeAlign: widget.ringStrokeAlign,
        twoTone: widget.twoToneRing,
        child: label == null
            ? widget.child
            : ExcludeSemantics(child: widget.child),
      ),
    );
    if (label == null) return target;
    return Semantics(button: true, label: label, child: target);
  }
}

/// The ring's paint on its own, for a control that handles its own focus and
/// activation and only needs the indicator ([PressableButton], #9191).
/// [show] is the caller's to gate on [FocusRingTapTarget.highlightsEnabled].
class FocusRing extends StatelessWidget {
  final OutlinedBorder shape;
  final bool show;

  /// See [FocusRingTapTarget.ringStrokeAlign].
  final double strokeAlign;

  /// See [FocusRingTapTarget.twoToneRing].
  final bool twoTone;
  final Widget child;

  const FocusRing({
    required this.shape,
    required this.show,
    required this.child,
    this.strokeAlign = BorderSide.strokeAlignInside,
    this.twoTone = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final outside = strokeAlign == BorderSide.strokeAlignOutside;
    return _RingBand(
      shape: shape,
      side: twoTone
          ? BorderSide(
              color: outside
                  ? FocusRingTapTarget.twoToneInner
                  : FocusRingTapTarget.twoToneOuter,
              width: FocusRingTapTarget.ringWidth,
            )
          : FocusRingTapTarget.ringSide(context),
      strokeAlign: strokeAlign,
      show: show,
      // The two-tone ring's band away from the edge: painted first at double
      // width, so the edge band above it leaves one [ringWidth] of it
      // showing. Always mounted, so gaining focus never changes the tree.
      child: _RingBand(
        shape: shape,
        side: BorderSide(
          color: outside
              ? FocusRingTapTarget.twoToneOuter
              : FocusRingTapTarget.twoToneInner,
          width: 2 * FocusRingTapTarget.ringWidth,
        ),
        strokeAlign: strokeAlign,
        show: show && twoTone,
        child: child,
      ),
    );
  }
}

class _RingBand extends StatelessWidget {
  final OutlinedBorder shape;
  final BorderSide side;
  final double strokeAlign;
  final bool show;
  final Widget child;

  const _RingBand({
    required this.shape,
    required this.side,
    required this.strokeAlign,
    required this.show,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: ShapeDecoration(
      shape: shape.copyWith(
        side: show ? side.copyWith(strokeAlign: strokeAlign) : BorderSide.none,
      ),
    ),
    child: child,
  );
}

/// An [OutlinedBorder] that traces [outline], so a focus ring can follow a
/// mark's own silhouette (the level shield, the hexagon badge) rather than
/// draw a circle around it, the look #8067 removed (#9114). [outline] must be
/// a static or top-level function so two borders on one outline compare equal.
class PathBorder extends OutlinedBorder {
  final Path Function(Rect rect) outline;

  const PathBorder({required this.outline, super.side});

  @override
  EdgeInsetsGeometry get dimensions =>
      EdgeInsets.all(side.strokeInset.clamp(0.0, double.infinity));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => outline(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => outline(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    final path = outline(rect);
    // A path has no offset operation, so a band inside or outside the outline
    // is a double-width stroke clipped to that side of it.
    final centered = side.strokeAlign == BorderSide.strokeAlignCenter;
    canvas.save();
    if (side.strokeAlign == BorderSide.strokeAlignInside) {
      canvas.clipPath(path);
    } else if (side.strokeAlign == BorderSide.strokeAlignOutside) {
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect.inflate(2 * side.width))
          ..addPath(path, Offset.zero),
      );
    }
    canvas.drawPath(
      path,
      side.toPaint()
        ..strokeWidth = centered ? side.width : 2 * side.width
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  PathBorder copyWith({BorderSide? side}) =>
      PathBorder(outline: outline, side: side ?? this.side);

  @override
  PathBorder scale(double t) =>
      PathBorder(outline: outline, side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is PathBorder && other.outline == outline && other.side == side;

  @override
  int get hashCode => Object.hash(outline, side);
}
