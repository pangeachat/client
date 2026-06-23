import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// Mobile course view: the persistent world map shows through underneath, and
/// the course detail rides in a draggable bottom sheet over it (the Maps-style
/// "map + expandable panel" pattern). Two rest positions:
///  - **peek** — handle + course title + tab row, sized to clear the bottom
///    nav, with the map (course-scoped pins) visible above;
///  - **full** — the sheet fills the body so the whole course detail is
///    usable.
///
/// The sheet is driven by the grab handle (drag to resize, tap to toggle) so
/// the course detail's own per-tab scrolling stays independent. Lives only on
/// narrow screens; wide screens keep the two-column layout.
class MobileCourseSheet extends StatefulWidget {
  /// The course detail (the route's course view) shown inside the sheet.
  final Widget child;

  const MobileCourseSheet({required this.child, super.key});

  @override
  State<MobileCourseSheet> createState() => _MobileCourseSheetState();
}

class _MobileCourseSheetState extends State<MobileCourseSheet> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  /// Collapsed height: enough for the handle + the course header (title, the
  /// language/level/modules metadata row, and the tab row beneath it). Sized to
  /// clear that header so the peek doesn't overflow it; drag up for the body.
  static const double _peekHeight = 240.0;

  static const Duration _snapDuration = Duration(milliseconds: 240);

  double _peekFraction(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return 0.25;
    return (_peekHeight / height).clamp(0.12, 0.9);
  }

  void _animateTo(double size) {
    if (!_controller.isAttached) return;
    _controller.animateTo(size, duration: _snapDuration, curve: Curves.easeOut);
  }

  /// Tap the handle: toggle between peek and full.
  void _toggle() {
    final peek = _peekFraction(context);
    final expanded = _controller.isAttached && _controller.size > peek + 0.05;
    _animateTo(expanded ? peek : 1.0);
  }

  void _onDrag(DragUpdateDetails details) {
    if (!_controller.isAttached) return;
    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;
    final peek = _peekFraction(context);
    // Drag up (negative delta) grows the sheet.
    final next = (_controller.size - details.primaryDelta! / height).clamp(
      peek,
      1.0,
    );
    _controller.jumpTo(next);
  }

  /// On release, settle to the nearer of peek / full.
  void _onDragEnd(DragEndDetails details) {
    if (!_controller.isAttached) return;
    final peek = _peekFraction(context);
    final midpoint = (peek + 1.0) / 2;
    _animateTo(_controller.size >= midpoint ? 1.0 : peek);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peek = _peekFraction(context);
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: peek,
      minChildSize: peek,
      maxChildSize: 1.0,
      // Snapping is driven by the handle gestures below, not content scroll, so
      // the course detail's per-tab scroll views stay independent.
      snap: false,
      builder: (context, scrollController) {
        return Material(
          color: theme.colorScheme.surface,
          elevation: 8.0,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Grab handle: drag to resize, tap to toggle peek/full. Exposed to
              // assistive tech as a single named button that runs the toggle
              // (the drag is pointer-only); without this the bare GestureDetector
              // is an unnamed actionable element (axe `aria-command-name`).
              Semantics(
                button: true,
                label: L10n.of(context).resizeCoursePanel,
                onTap: _toggle,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    onVerticalDragUpdate: _onDrag,
                    onVerticalDragEnd: _onDragEnd,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Center(
                        child: Container(
                          width: 36.0,
                          height: 4.0,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.4,
                            ),
                            borderRadius: BorderRadius.circular(2.0),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
