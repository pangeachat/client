import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/pangea_icon_button.dart';

/// The cavity's resting heights, as a fraction of [MobileNavWidget.maxHeightFraction]:
/// rail-only, roughly half the growth bound, or the full bound.
enum NavCavityHeight { collapsed, half, full }

/// Single-column bottom chrome (world_v2): one floating rounded-corner box
/// anchored to the bottom of the safe area, combining the 4-item nav rail
/// (World / Chats / Courses / course shortcut) with an expandable cavity above
/// it that hosts the active section or course card. Replaces the old
/// `MobileBottomNav` + `MobileCourseSheet` pair with the single widget the
/// design calls for. See "Single-column bottom nav" in `routing.instructions.md`.
///
/// This widget is purely presentational: it reports taps and drag-driven
/// height changes upward, and the shell (via [onSectionTap] / [onCavityClose])
/// is the one that actually navigates. The rail row stays visible and
/// tappable at every cavity height.
class MobileNavWidget extends StatefulWidget {
  /// Which rail item is highlighted — computed by the shell (`sectionFor`).
  final AppSection activeSection;

  /// The 4th rail item's visual (an add-course icon, a single course avatar,
  /// or the most-recently-opened course avatar) — resolved by the shell.
  final Widget? courseShortcutIcon;

  /// Semantic label / tooltip for the course shortcut.
  final String courseShortcutLabel;

  final VoidCallback onCourseShortcutTap;

  /// World / Chats / Courses rail taps. The shell performs the actual token
  /// navigation (`WorkspaceNav.setSection`, etc).
  final void Function(AppSection section) onSectionTap;

  /// The open section/course content hosted in the cavity. Null means nothing
  /// is cavity-hosted (rail-only, no matter the last height).
  final Widget? cavityChild;

  /// Height-memory identity for the current [cavityChild]: a course space id,
  /// or a fixed key like `'chats'` / `'courses'`. A different key opens at its
  /// own default rather than inheriting the previous key's height.
  final String? cavityKey;

  /// True for a course card (opens at a small peek by default); false for a
  /// section (opens at half by default).
  final bool cavityDefaultsToPeek;

  /// Header title shown centered above the cavity content.
  final String? cavityTitle;

  /// The header's X — the panel's real close (drops the shell's token). Null
  /// hides the X (nothing to close).
  final VoidCallback? onCavityClose;

  /// Upper growth bound for the cavity, as a fraction of the screen height,
  /// computed by the shell (so the search bar + analytics bar stay visible
  /// above it at full height).
  final double maxHeightFraction;

  /// Rendered directly above the rounded box (outside it, small gap), riding
  /// the widget's expansion for free — the floating search bar's slot
  /// (routing.instructions.md → Single-column search bar). Null renders
  /// nothing.
  final Widget? topAttachment;

  const MobileNavWidget({
    required this.activeSection,
    this.courseShortcutIcon,
    required this.courseShortcutLabel,
    required this.onCourseShortcutTap,
    required this.onSectionTap,
    this.cavityChild,
    this.cavityKey,
    this.cavityDefaultsToPeek = false,
    this.cavityTitle,
    this.onCavityClose,
    required this.maxHeightFraction,
    this.topAttachment,
    super.key,
  });

  /// Last settled height per [cavityKey], surviving disposal when a full-screen
  /// surface (a live chat, an activity) mounts over this widget — mirrors
  /// `MobileCourseSheet._expandedBySheet` (#7332), generalized to any section
  /// or course key and to three rest states instead of two.
  static final Map<String, NavCavityHeight> _heightByKey = {};

  @visibleForTesting
  static void resetHeightMemoryForTest() => _heightByKey.clear();

  @override
  State<MobileNavWidget> createState() => _MobileNavWidgetState();
}

class _MobileNavWidgetState extends State<MobileNavWidget> {
  static const double _railHeight = 64.0;
  static const double _peekHeight = 240.0;
  static const Duration _animationDuration = Duration(milliseconds: 240);

  /// Current fraction of [MobileNavWidget.maxHeightFraction] the cavity is
  /// drawn at, animated toward whenever the target height changes.
  double _fraction = 0.0;
  double? _dragStartFraction;

  @override
  void initState() {
    super.initState();
    _fraction = _fractionFor(_restoreHeight());
  }

  @override
  void didUpdateWidget(MobileNavWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final openedNow =
        oldWidget.cavityChild == null && widget.cavityChild != null;
    final closedNow =
        oldWidget.cavityChild != null && widget.cavityChild == null;
    final keyChanged =
        widget.cavityChild != null && oldWidget.cavityKey != widget.cavityKey;

    if (closedNow) {
      setState(() => _fraction = 0.0);
    } else if (openedNow || keyChanged) {
      setState(() => _fraction = _fractionFor(_restoreHeight()));
    }
  }

  NavCavityHeight _restoreHeight() {
    final key = widget.cavityKey;
    if (key == null) return NavCavityHeight.collapsed;
    return MobileNavWidget._heightByKey[key] ?? _defaultHeight();
  }

  NavCavityHeight _defaultHeight() => widget.cavityDefaultsToPeek
      ? NavCavityHeight.collapsed
      : NavCavityHeight.half;

  void _remember(NavCavityHeight height) {
    final key = widget.cavityKey;
    if (key == null) return;
    MobileNavWidget._heightByKey[key] = height;
  }

  /// The peek height (course default) is a small static inset, like
  /// `MobileCourseSheet`'s 240px peek — not zero, so the header + a little
  /// content shows, but well short of half.
  double _peekFraction(double maxHeightPx) {
    if (maxHeightPx <= 0) return 0.2;
    return (_peekHeight / maxHeightPx).clamp(0.05, 0.9);
  }

  double _fractionForState(NavCavityHeight height, double maxHeightPx) {
    switch (height) {
      case NavCavityHeight.collapsed:
        return widget.cavityDefaultsToPeek ? _peekFraction(maxHeightPx) : 0.0;
      case NavCavityHeight.half:
        return 0.5;
      case NavCavityHeight.full:
        return 1.0;
    }
  }

  // Resolved lazily against the current context in build(); stored here so
  // gesture callbacks (no BuildContext dependency) can reuse the last-known
  // value between frames.
  double _lastMaxHeightPx = 0.0;

  double _fractionFor(NavCavityHeight height) =>
      _fractionForState(height, _lastMaxHeightPx);

  void _animateToFraction(double fraction) {
    setState(() => _fraction = fraction.clamp(0.0, 1.0));
  }

  void _openAt(NavCavityHeight height) {
    _remember(height);
    _animateToFraction(_fractionForState(height, _lastMaxHeightPx));
  }

  /// Handle tap: toggles half <-> full (the #7128 pattern) — reachable without
  /// a drag gesture for keyboard / switch access.
  void _toggleHandle() {
    final expanded = _fraction > 0.75;
    _openAt(expanded ? NavCavityHeight.half : NavCavityHeight.full);
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartFraction = _fraction;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_lastMaxHeightPx <= 0) return;
    final start = _dragStartFraction ?? _fraction;
    final deltaFraction = -details.primaryDelta! / _lastMaxHeightPx;
    setState(() {
      _fraction = (_fraction + deltaFraction).clamp(0.0, 1.0);
    });
    _dragStartFraction = start;
  }

  void _onDragEnd(DragEndDetails details) {
    // Settle to the nearest of the three rest fractions.
    final peek = widget.cavityDefaultsToPeek
        ? _peekFraction(_lastMaxHeightPx)
        : 0.0;
    final candidates = <NavCavityHeight, double>{
      NavCavityHeight.collapsed: peek,
      NavCavityHeight.half: 0.5,
      NavCavityHeight.full: 1.0,
    };
    NavCavityHeight nearest = NavCavityHeight.half;
    double nearestDistance = double.infinity;
    for (final entry in candidates.entries) {
      final distance = (entry.value - _fraction).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = entry.key;
      }
    }
    _openAt(nearest);
  }

  /// Tapping outside the cavity — an ephemeral collapse, NOT a close: the
  /// shell's tokens stay, so re-expanding restores the same height.
  void _collapseEphemeral() {
    setState(() => _fraction = 0.0);
  }

  void _onRailItemTap(AppSection section) {
    if (widget.cavityChild != null && section == widget.activeSection) {
      // Tapping the already-active rail item while expanded collapses it;
      // while collapsed (with content available) re-expands to the
      // remembered height.
      if (_fraction > 0.01) {
        setState(() => _fraction = 0.0);
      } else {
        _openAt(_restoreHeight());
      }
      return;
    }
    // A different rail item: the shell handles token navigation and the next
    // build's didUpdateWidget resolves the resulting height.
    widget.onSectionTap(section);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeightPx = screenHeight * widget.maxHeightFraction;
    _lastMaxHeightPx = maxHeightPx;

    final cavityHeightPx = widget.cavityChild == null
        ? 0.0
        : (maxHeightPx * _fraction).clamp(0.0, maxHeightPx);

    final isExpanded = widget.cavityChild != null && _fraction > 0.01;

    return Stack(
      children: [
        // Tap-outside barrier: only present while expanded, so it never
        // intercepts taps meant for whatever is behind the collapsed widget.
        if (isExpanded)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _collapseEphemeral,
              child: const SizedBox.expand(),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The floating search bar rides here, above the rounded box,
                  // keeping its gap at every cavity height (the doc's "rides
                  // upward as the widget expands").
                  if (widget.topAttachment != null) ...[
                    widget.topAttachment!,
                    const SizedBox(height: 8.0),
                  ],
                  Material(
                    color: theme.colorScheme.surface,
                    elevation: 4,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius,
                        ),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.cavityChild != null)
                            AnimatedContainer(
                              duration: _animationDuration,
                              curve: Curves.easeOut,
                              height: cavityHeightPx,
                              child: cavityHeightPx <= 0
                                  ? null
                                  : ClipRect(
                                      child: _NavCavity(
                                        title: widget.cavityTitle,
                                        onClose: widget.onCavityClose,
                                        onHandleTap: _toggleHandle,
                                        onDragStart: _onDragStart,
                                        onDragUpdate: _onDragUpdate,
                                        onDragEnd: _onDragEnd,
                                        child: widget.cavityChild!,
                                      ),
                                    ),
                            ),
                          SizedBox(
                            height: _railHeight,
                            child: Semantics(
                              label: l10n.navOptionsLabel,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  PangeaIconButton(
                                    selected:
                                        widget.activeSection ==
                                        AppSection.world,
                                    tooltip: l10n.world,
                                    onPressed: () =>
                                        _onRailItemTap(AppSection.world),
                                  ),
                                  _RailButton(
                                    icon: Icons.forum_outlined,
                                    selectedIcon: Icons.forum,
                                    selected:
                                        widget.activeSection ==
                                        AppSection.chats,
                                    tooltip: l10n.allChats,
                                    onTap: () =>
                                        _onRailItemTap(AppSection.chats),
                                  ),
                                  _RailButton(
                                    icon: Icons.map_outlined,
                                    selectedIcon: Icons.map,
                                    selected:
                                        widget.activeSection ==
                                        AppSection.courses,
                                    tooltip: l10n.courses,
                                    onTap: () =>
                                        _onRailItemTap(AppSection.courses),
                                  ),
                                  _CourseShortcutButton(
                                    icon: widget.courseShortcutIcon,
                                    label: widget.courseShortcutLabel,
                                    onTap: widget.onCourseShortcutTap,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One rail item styled like `MobileBottomNav`'s `_NavButton`: the selected
/// treatment tints the icon with the primary colour and swaps to its filled
/// variant.
class _RailButton extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      onPressed: onTap,
      icon: Icon(
        selected ? selectedIcon : icon,
        color: selected ? theme.colorScheme.primary : null,
      ),
    );
  }
}

/// The 4th rail slot: the shell-resolved course shortcut visual (an add icon,
/// a single course avatar, or the most-recently-opened course).
class _CourseShortcutButton extends StatelessWidget {
  final Widget? icon;
  final String label;
  final VoidCallback onTap;

  const _CourseShortcutButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: icon ?? const Icon(Icons.add),
        ),
      ),
    );
  }
}

/// The expandable cavity: a drag handle (also a labeled toggle button, the
/// #7128 pattern) then a header row ([X close] [centered title]), then the
/// hosted section/course content, scrollable.
class _NavCavity extends StatelessWidget {
  final String? title;
  final VoidCallback? onClose;
  final VoidCallback onHandleTap;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final Widget child;

  const _NavCavity({
    required this.title,
    required this.onClose,
    required this.onHandleTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Column(
      children: [
        // Grab handle: drag to resize, tap to toggle half/full. Exposed to
        // assistive tech as a single named button that runs the toggle (the
        // drag is pointer-only) — mirrors `MobileCourseSheet`'s handle (#7128).
        Semantics(
          button: true,
          label: l10n.resizeCoursePanel,
          onTap: onHandleTap,
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onHandleTap,
              onVerticalDragStart: onDragStart,
              onVerticalDragUpdate: onDragUpdate,
              onVerticalDragEnd: onDragEnd,
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
        // Header: [X close] [centered title]. The X is the panel's real
        // close — it calls back to the shell, which drops the token.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            children: [
              SizedBox(
                width: 40.0,
                child: onClose == null
                    ? null
                    : IconButton(
                        tooltip: title != null && title!.isNotEmpty
                            ? l10n.closeNamed(title!)
                            : l10n.close,
                        icon: const Icon(Icons.close),
                        onPressed: onClose,
                      ),
              ),
              Expanded(
                child: Text(
                  title ?? '',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 40.0),
            ],
          ),
        ),
        Expanded(child: SingleChildScrollView(child: child)),
      ],
    );
  }
}
