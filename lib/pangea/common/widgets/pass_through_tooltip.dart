import 'dart:async';

import 'package:flutter/material.dart';

/// [Tooltip]'s hover label, minus the pointer blocking.
///
/// [Tooltip] keeps its overlay alive while the pointer is on it by wrapping the
/// overlay in an opaque `MouseRegion`, which swallows every pointer event that
/// lands on the label — and it has no knob for this: its `ignorePointer` covers
/// only the box inside that region. Wherever the label can end up under the
/// cursor mid-gesture, that kills the gesture: a scroll-wheel zoom on the world
/// map once a pin's label drifts under the cursor
/// ([#8591](https://github.com/pangeachat/client/issues/8591)), a scroll of
/// the nav rail once an item's label is carried up under it
/// ([#8857](https://github.com/pangeachat/client/issues/8857)).
///
/// The label here sits behind an [IgnorePointer], so whatever it covers keeps
/// every event and the label is purely something to look at. [child] still
/// carries [message] as its semantic tooltip — its accessible name when it has
/// no visible text — unless [excludeFromSemantics]; the label itself stays out
/// of the semantics tree, as it does under [Tooltip].
///
/// Hover-only: there is no long-press trigger, since a touch device has no
/// cursor for the label to block.
class PassThroughTooltip extends StatefulWidget {
  final String message;
  final Widget child;

  /// How long the pointer must rest on [child] before the label shows, so
  /// items sweeping under the cursor mid-scroll don't each spawn one (#8215).
  final Duration waitDuration;

  /// Set when [child] already names itself, so the message isn't announced
  /// twice.
  final bool excludeFromSemantics;

  const PassThroughTooltip({
    super.key,
    required this.message,
    required this.child,
    this.waitDuration = Duration.zero,
    this.excludeFromSemantics = false,
  });

  @override
  State<PassThroughTooltip> createState() => _PassThroughTooltipState();
}

class _PassThroughTooltipState extends State<PassThroughTooltip> {
  final OverlayPortalController _controller = OverlayPortalController();
  Timer? _showTimer;

  void _scheduleShow(PointerEvent _) {
    _showTimer?.cancel();
    _showTimer = Timer(widget.waitDuration, _controller.show);
  }

  void _hide(PointerEvent _) {
    _showTimer?.cancel();
    if (_controller.isShowing) _controller.hide();
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _scheduleShow,
      onExit: _hide,
      // A press on the child dismisses the label, as it does under Tooltip —
      // opaque, as there, so the press counts even where the child itself
      // has nothing hittable.
      child: Listener(
        onPointerDown: _hide,
        behavior: HitTestBehavior.opaque,
        child: OverlayPortal.overlayChildLayoutBuilder(
          controller: _controller,
          // A child mid-animation (a map pin's entry pop-in, exit shrink) has
          // a collapsed paint transform, and transforming through it puts the
          // label at NaN.
          overlayChildBuilder: (context, info) =>
              info.childPaintTransform.determinant() == 0.0
              ? const SizedBox.shrink()
              : _PassThroughTooltipLabel(
                  message: widget.message,
                  target: MatrixUtils.transformPoint(
                    info.childPaintTransform,
                    info.childSize.center(Offset.zero),
                  ),
                ),
          child: Semantics(
            tooltip: widget.excludeFromSemantics ? null : widget.message,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The label box: [Tooltip]'s own default look, drawn pointer-inert over the
/// whole overlay.
class _PassThroughTooltipLabel extends StatelessWidget {
  final String message;

  /// The child's centre, in the overlay's coordinates.
  final Offset target;

  const _PassThroughTooltipLabel({required this.message, required this.target});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Tooltip's defaults are platform-sized — compact on desktop, roomier on
    // touch platforms — kept so the label reads like every other tooltip in
    // the app.
    final isDesktop = switch (theme.platform) {
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.windows => true,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => false,
    };
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomSingleChildLayout(
          delegate: _PassThroughTooltipLayout(target),
          child: Container(
            constraints: BoxConstraints(minHeight: isDesktop ? 24.0 : 32.0),
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 8.0 : 16.0,
              vertical: 4.0,
            ),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.grey[700]!).withValues(
                alpha: 0.9,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(4)),
            ),
            child: Center(
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.black : Colors.white,
                  fontSize: isDesktop ? 12.0 : 14.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Places the label where [Tooltip] would: below the child's centre, flipped
/// above it when there isn't room, clamped to the screen.
class _PassThroughTooltipLayout extends SingleChildLayoutDelegate {
  /// [Tooltip]'s default gap between the child's centre and the label.
  static const double _verticalOffset = 24.0;

  final Offset target;

  const _PassThroughTooltipLayout(this.target);

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
  bool shouldRelayout(_PassThroughTooltipLayout oldDelegate) =>
      target != oldDelegate.target;
}
