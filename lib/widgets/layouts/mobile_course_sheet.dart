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

  /// Stable identity of the content in the sheet (the course space id, or an
  /// activity id when the sheet hosts a standalone activity). The expand/peek
  /// state is remembered PER [sheetId] so that opening a chat over the sheet —
  /// which disposes it — and then closing the chat restores the size the learner
  /// left this course at, while a *different* course still opens at peek (#7332).
  final String sheetId;

  const MobileCourseSheet({
    required this.child,
    required this.sheetId,
    super.key,
  });

  /// Last settled expand state per [sheetId], surviving the sheet's disposal
  /// when a chat opens over it (#7332). Only one mobile sheet exists at a time
  /// (single column), and entries are keyed by course/activity so switching
  /// courses doesn't inherit another's size. Defaults to peek (absent key →
  /// collapsed).
  static final Map<String, bool> _expandedBySheet = {};

  @visibleForTesting
  static void resetExpandedMemoryForTest() => _expandedBySheet.clear();

  @override
  State<MobileCourseSheet> createState() => _MobileCourseSheetState();
}

class _MobileCourseSheetState extends State<MobileCourseSheet> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  void _rememberExpanded(bool expanded) =>
      MobileCourseSheet._expandedBySheet[widget.sheetId] = expanded;

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
    _rememberExpanded(!expanded);
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
    final expand = _controller.size >= midpoint;
    _animateTo(expand ? 1.0 : peek);
    _rememberExpanded(expand);
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
    // Restore the size this course/activity was left at (#7332): a fresh mount
    // after a chat closed over the sheet reopens expanded if that's how the
    // learner left it, otherwise at peek.
    final restoreExpanded =
        MobileCourseSheet._expandedBySheet[widget.sheetId] ?? false;
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: restoreExpanded ? 1.0 : peek,
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
          // The content must be a scroll view bound to the sheet's
          // [scrollController]: a DraggableScrollableController only ATTACHES
          // once a scrollable consumes that controller. A plain Column never
          // attaches it, so `isAttached` stays false and every animateTo/jumpTo
          // silently no-ops — the handle looked live but did nothing (#7102).
          // Scrolling is disabled here on purpose: the handle drives resize and
          // the course detail scrolls on its own controllers, so this outer view
          // must only serve to attach the controller, never scroll-to-resize.
          child: CustomScrollView(
            controller: scrollController,
            physics: const NeverScrollableScrollPhysics(),
            slivers: [
              // Grab handle: drag to resize, tap to toggle peek/full. Exposed to
              // assistive tech as a single named button that runs the toggle
              // (the drag is pointer-only); without this the bare GestureDetector
              // is an unnamed actionable element (axe `aria-command-name`, #7128).
              SliverToBoxAdapter(
                child: Semantics(
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
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2.0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // The course detail fills the rest of the sheet (as the old
              // Expanded did) and scrolls internally on its own controllers.
              SliverFillRemaining(
                hasScrollBody: true,
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
