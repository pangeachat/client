import 'package:flutter/material.dart';

/// A map pin's title on hover — what [Tooltip] shows, minus the pointer
/// blocking.
///
/// [Tooltip] keeps its overlay alive while the pointer is on it by wrapping the
/// overlay in an opaque `MouseRegion`, which swallows every event landing on
/// the label. Over the map that kills a scroll-wheel zoom the moment the label
/// drifts under the cursor, and eats clicks meant for the pin the label belongs
/// to ([#8591](https://github.com/pangeachat/client/issues/8591)). The label
/// here sits behind an [IgnorePointer], so the pin and the map keep every
/// event and the label is purely something to look at — it also stays out of
/// the semantics tree, since the pin below already names itself.
class WorldMapPinTooltip extends StatefulWidget {
  final String message;
  final Widget child;

  const WorldMapPinTooltip({
    super.key,
    required this.message,
    required this.child,
  });

  @override
  State<WorldMapPinTooltip> createState() => _WorldMapPinTooltipState();
}

class _WorldMapPinTooltipState extends State<WorldMapPinTooltip> {
  final OverlayPortalController _controller = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _controller.show(),
      onExit: (_) => _controller.hide(),
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _controller,
        // A pin mid-animation (entry pop-in, exit shrink) has a collapsed paint
        // transform, and transforming through it puts the label at NaN.
        overlayChildBuilder: (context, info) =>
            info.childPaintTransform.determinant() == 0.0
            ? const SizedBox.shrink()
            : _WorldMapPinLabel(
                message: widget.message,
                target: MatrixUtils.transformPoint(
                  info.childPaintTransform,
                  info.childSize.center(Offset.zero),
                ),
              ),
        child: widget.child,
      ),
    );
  }
}

/// The label box: [Tooltip]'s own default look, drawn pointer-inert over the
/// whole overlay.
class _WorldMapPinLabel extends StatelessWidget {
  final String message;

  /// The pin's centre, in the overlay's coordinates.
  final Offset target;

  const _WorldMapPinLabel({required this.message, required this.target});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomSingleChildLayout(
          delegate: _WorldMapPinLabelLayout(target),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(
              // Tooltip's default box, kept so a pin's label still reads like
              // every other tooltip in the app.
              color: (isDark ? Colors.white : Colors.grey[700]!).withValues(
                alpha: 0.9,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(4)),
            ),
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.black : Colors.white,
                fontSize: switch (theme.platform) {
                  TargetPlatform.macOS ||
                  TargetPlatform.linux ||
                  TargetPlatform.windows => 12.0,
                  TargetPlatform.android ||
                  TargetPlatform.fuchsia ||
                  TargetPlatform.iOS => 14.0,
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Places the label where [Tooltip] would: below the pin's centre, flipped
/// above it when there isn't room, clamped to the screen.
class _WorldMapPinLabelLayout extends SingleChildLayoutDelegate {
  /// [Tooltip]'s default gap between the pin's centre and the label.
  static const double _verticalOffset = 24.0;

  final Offset target;

  const _WorldMapPinLabelLayout(this.target);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => positionDependentBox(
    size: size,
    childSize: childSize,
    target: target,
    verticalOffset: _verticalOffset,
    preferBelow: true,
  );

  @override
  bool shouldRelayout(_WorldMapPinLabelLayout oldDelegate) =>
      target != oldDelegate.target;
}
