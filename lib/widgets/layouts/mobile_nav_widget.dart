import 'dart:math';

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
/// height changes upward, and the shell (via [onSectionTap]) is the one that
/// actually navigates. The cavity adds only the drag handle — every hosted
/// surface brings its own header and close/back affordance. The rail row
/// stays visible and tappable at every cavity height. Mount it
/// `Positioned.fill`: the widget bottom-aligns its own box, and its
/// tap-outside barrier needs the whole screen to collapse on a map tap.
class MobileNavWidget extends StatefulWidget {
  /// Which rail item is highlighted — computed by the shell (`sectionFor`).
  final AppSection activeSection;

  /// The 4th rail item's visual (an add-course icon, a single course avatar,
  /// or the most-recently-opened course avatar) — resolved by the shell.
  final Widget? courseShortcutIcon;

  /// Semantic label / tooltip for the course shortcut.
  final String courseShortcutLabel;

  /// The shortcut's course is the active workspace context: the shortcut gets
  /// the highlight and the Courses item stays unlit (mirrors the web rail
  /// highlighting the specific course avatar over the section icon).
  final bool courseShortcutSelected;

  final VoidCallback onCourseShortcutTap;

  /// World / Chats / Courses rail taps. The shell performs the actual token
  /// navigation (`WorkspaceNav.setSection`, etc).
  final void Function(AppSection section) onSectionTap;

  /// Wraps the Chats rail item with the all-chats unread badge, so the narrow
  /// tab carries the same count the web rail's Chats item wears (#8129).
  /// Injected by the shell — which owns the Matrix lookups and the sync-driven
  /// rebuilds — so this widget stays presentational. Null renders the plain
  /// button.
  final Widget Function(Widget child)? chatsBadgeBuilder;

  /// The open section/course content hosted in the cavity. Null means nothing
  /// is cavity-hosted (rail-only, no matter the last height).
  final Widget? cavityChild;

  /// Which rail item's OWN surface the cavity hosts — [AppSection.chats] for
  /// the chat list, [AppSection.courses] for the add-course hub, null for
  /// anything else (a course sheet, an activity plan). Drives the
  /// tap-the-active-item toggle: [activeSection] alone can't, because the
  /// highlight resolves a whole course context to Courses while the cavity
  /// hosts a specific course, and the Courses tap must then NAVIGATE to the
  /// hub, not toggle the course sheet (#7537).
  final AppSection? cavitySection;

  /// True when the cavity hosts the shortcut's own course sheet: the shortcut
  /// tap then toggles collapse/re-expand instead of a same-URL no-op (#7537).
  final bool courseShortcutHostsCavity;

  /// Height-memory identity for the current [cavityChild]: a course space id,
  /// or a fixed key like `'chats'` / `'courses'`. A different key opens at its
  /// own default rather than inheriting the previous key's height.
  final String? cavityKey;

  /// The active COURSE context (`?c=` / `activeSpaceId`), or null when the
  /// workspace isn't course-scoped. This is what says a course is still "open":
  /// a chat or an activity opened from a course keeps the same context (only the
  /// cavity — hence [cavityKey] — swaps), and even closing the course card keeps
  /// it; the context leaves a course only via World or choosing another course
  /// (routing.instructions.md — "scope is reset only by the World control or by
  /// choosing a different course, never by closing a panel"). A course's
  /// remembered height is forgotten exactly when the context leaves it, so
  /// sub-navigation preserves it (#7332) while a genuinely fresh course open
  /// starts at peek (#7609). See [didUpdateWidget].
  final String? cavityContextId;

  /// True for a course card (opens at a small peek by default); false for a
  /// section (opens at half by default).
  final bool cavityDefaultsToPeek;

  /// Upper growth bound for the cavity, as a fraction of the screen height,
  /// computed by the shell (so the search bar + analytics bar stay visible
  /// above it at full height).
  final double maxHeightFraction;

  /// Content-fit height for the DEFAULT (half) rest state, in pixels: the
  /// cavity opens just tall enough to show all of its content, capped by
  /// [maxHeightFraction] (routing.instructions.md — the chats sheet shows all
  /// its chats by default). Null keeps the plain half-of-max default. The
  /// full state is unaffected — dragging up still grows to the cap.
  final double? preferredCavityHeightPx;

  /// Rendered directly above the rounded box (outside it, small gap), riding
  /// the widget's expansion for free — the floating search bar's slot
  /// (routing.instructions.md → Single-column search bar). Null renders
  /// nothing.
  final Widget? topAttachment;

  /// When non-null, a dismissal gesture — dragging the sheet fully down (and,
  /// unless [mapStaysLive], tapping outside it) — CLOSES the hosted surface
  /// (the shell navigates its token away) instead of the ephemeral collapse.
  /// Wired for the activity plan sheet, where dismissing must also clear the
  /// map's activity focus (#7614; world-map.instructions.md — focus is
  /// cleared by closing the plan or focusing another activity). Null keeps
  /// collapse-not-close, the design for section sheets and the course card.
  final VoidCallback? onDismissed;

  /// The map stays interactive around this cavity: no tap-outside barrier is
  /// mounted, so taps, pans, and pinches in the exposed map area fall through
  /// to the map below — tapping another pin selects it directly, and panning
  /// never collapses or dismisses the sheet. Wired for the map-ground
  /// cavities (the activity plan and the course card), where the map is the
  /// ground the sheet rides over; dismissal is the drag-down handle or the
  /// sheet's own close control. Section sheets (chats, the hub) keep the
  /// barrier: tap-outside collapse is their whole dismissal model.
  final bool mapStaysLive;

  /// Fires when the hosted cavity settles at (or leaves) its FULL height, so
  /// the shell can drop the floating search bar over a full course sheet and
  /// hand that reserved strip to the course content (#7697). Latched to the
  /// settled rest state — it deliberately does NOT toggle mid-drag, so the
  /// reserved height (and thus the drag's coordinate space) stays stable while
  /// the finger moves.
  final ValueChanged<bool>? onCavityFullChanged;

  /// The keyboard's overlap BEYOND the bottom safe area, computed by the shell
  /// (which reads `viewInsets` above its Scaffold — a resizing Scaffold hides it
  /// from the body — and nets out the home-indicator inset the SafeArea stops
  /// reserving once the keyboard covers it). Trimmed from the cavity —
  /// INSTANTLY, not through the rest-height animation — so the top holds its
  /// position the whole time the keyboard opens: no jump-then-readjust, and no
  /// settle a few pt low (#7754). Zero when no keyboard is up.
  final double keyboardInset;

  const MobileNavWidget({
    required this.activeSection,
    this.courseShortcutIcon,
    required this.courseShortcutLabel,
    this.courseShortcutSelected = false,
    required this.onCourseShortcutTap,
    required this.onSectionTap,
    this.chatsBadgeBuilder,
    this.cavityChild,
    this.cavitySection,
    this.courseShortcutHostsCavity = false,
    this.cavityKey,
    this.cavityContextId,
    this.cavityDefaultsToPeek = false,
    required this.maxHeightFraction,
    this.preferredCavityHeightPx,
    this.topAttachment,
    this.onDismissed,
    this.mapStaysLive = false,
    this.onCavityFullChanged,
    this.keyboardInset = 0.0,
    super.key,
  });

  /// The rail row's fixed height — the box below the cavity. Public because
  /// [maxHeightFraction] caps the CAVITY only; the shell must add this (plus
  /// its own margins) when reserving vertical space, or a fully-expanded
  /// widget overshoots the reservation by exactly this much.
  static const double railRowHeight = 64.0;

  /// Last settled height per [cavityKey], surviving disposal when a full-screen
  /// surface (a live chat, an activity) mounts over this widget — mirrors
  /// `MobileCourseSheet._expandedBySheet` (#7332), generalized to any section
  /// or course key and to three rest states instead of two. A course entry is
  /// dropped when the course CONTEXT leaves it (World / a different course), so a
  /// fresh course open starts at peek (#7609; [didUpdateWidget]) while opening a
  /// chat or activity from the course — or a chat that only disposes this widget
  /// — keeps the context and restores the height on return (#7332). Section keys
  /// persist for the session (#7510).
  static final Map<String, NavCavityHeight> _heightByKey = {};

  @visibleForTesting
  static void resetHeightMemoryForTest() => _heightByKey.clear();

  @override
  State<MobileNavWidget> createState() => _MobileNavWidgetState();
}

class _MobileNavWidgetState extends State<MobileNavWidget> {
  static const double _railHeight = MobileNavWidget.railRowHeight;

  /// Anchors the cavity's outer sizing box — the box whose height is the
  /// animated rest height MINUS the (instant) keyboard trim. Tests read its
  /// rendered height to assert the keyboard behaviour (#7754).
  static const Key _cavityBoxKey = ValueKey('navCavityBox');

  /// The collapsed peek height for a course sheet (the only cavity that peeks).
  /// Sized to the course card's compact header — the drag handle plus the
  /// [X · title · share] row and the overall progress bar — so the collapsed
  /// default shows exactly the course identity + progress. The card itself
  /// drops its tabs/content below `_kCompactCardMaxHeight` (168px) so this short
  /// box never overflows; the tabs slide in as the learner drags up (#7597, the
  /// Figma mobile-default frame). Kept a touch under that threshold.
  static const double _peekHeight = 128.0;
  static const Duration _animationDuration = Duration(milliseconds: 240);

  /// The least the keyboard trim may leave of a cavity that HOLDS FOCUS — the
  /// drag handle plus one text-field row. Trimming past it drops the hosted
  /// surface entirely (see `showContent` in [build]), which disposes the
  /// focused field's node, which closes the keyboard, which un-trims the
  /// cavity, which remounts the field: the #8072 loop where a tapped input
  /// deselects itself. Applies only while something inside the cavity is
  /// focused, so the plain keyboard trim of #7754 is unchanged.
  static const double _focusedKeyboardFloor = 96.0;

  /// The rest stop the cavity currently sits at. Non-null means the drawn
  /// fraction is DERIVED from this each build ([_currentFraction]), so it
  /// tracks the live max height and content-fit hint — a cold mount, a
  /// viewport change, or a chat arriving while the sheet rests all resolve
  /// against fresh numbers. Null while the fraction is ad hoc (mid-drag, or
  /// an ephemeral tap-outside collapse), where [_fraction] holds the value.
  NavCavityHeight? _restState;

  /// Ad-hoc fraction, meaningful only while [_restState] is null.
  double _fraction = 0.0;
  double? _dragStartFraction;

  /// Whether the cavity is settled at full height, LATCHED across drags: it
  /// flips only when the sheet settles at a rest stop ([_openAt]) or the cavity
  /// opens / closes / changes key — never on the transient null rest state
  /// mid-drag. That keeps the shell's search-bar reservation (#7697) from
  /// thrashing (and the box from jumping) while the finger is dragging.
  bool _fullLatched = false;

  /// Last value handed to [MobileNavWidget.onCavityFullChanged]; the post-frame
  /// notify in [build] fires only on a real change.
  bool _reportedFull = false;

  /// Something inside [MobileNavWidget.cavityChild] holds focus — in practice a
  /// text input the learner just tapped. Drives both the grow-to-full below and
  /// the [_focusedKeyboardFloor] in [build].
  bool _cavityHasFocus = false;

  /// The grow-to-full has already fired for the current focus/keyboard episode,
  /// so a later rebuild does not undo a height the learner chose by dragging
  /// while the keyboard is still up. Cleared when focus or the keyboard leaves.
  bool _grewForKeyboard = false;

  @override
  void initState() {
    super.initState();
    _restState = _restoreHeight();
    _fullLatched = _restState == NavCavityHeight.full;
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

    // Forget a course's remembered height exactly when the course CONTEXT leaves
    // it — i.e. World or choosing a different course, the only two things that
    // reset scope (routing.instructions.md). That is the deterministic fresh
    // open (#7609). Everything that keeps the context — opening a chat or an
    // activity from the course, or even closing the course card — is still the
    // same course "open", so its height is preserved (#7332). Keyed by the OLD
    // context (== the leaving course's [cavityKey]); a chat covering the course
    // instead DISPOSES the widget with the context unchanged, so nothing is
    // cleared and the height is restored on return.
    final contextLeft =
        oldWidget.cavityContextId != null &&
        oldWidget.cavityContextId != widget.cavityContextId;
    if (contextLeft) {
      MobileNavWidget._heightByKey.remove(oldWidget.cavityContextId);
    }

    if (closedNow) {
      setState(() {
        _restState = null;
        _fraction = 0.0;
      });
      _fullLatched = false;
    } else if (openedNow || keyChanged) {
      final restored = _restoreHeight();
      setState(() => _restState = restored);
      _fullLatched = restored == NavCavityHeight.full;
    }
    // The keyboard arrives a frame or two after the focus that summoned it, so
    // this — not [_onCavityFocusChanged] alone — is where the grow usually
    // fires.
    _growForKeyboardIfNeeded();
    // A preferredCavityHeightPx change needs no handling: a resting sheet
    // derives its fraction from the current hint every build.
  }

  void _onCavityFocusChanged(bool hasFocus) {
    if (!mounted || _cavityHasFocus == hasFocus) return;
    setState(() => _cavityHasFocus = hasFocus);
    _growForKeyboardIfNeeded();
  }

  /// Grow the cavity to full while a hosted input holds focus and the software
  /// keyboard is up. At peek — or at a short content-fit half — the keyboard
  /// covers the whole cavity, leaving the learner typing into a field they
  /// cannot see, so full (the most room the widget has) is the only height that
  /// works. It mirrors the peek's own tap-to-expand (#7609), which a text
  /// field's tap otherwise claims for itself. Deliberately NOT remembered: the
  /// keyboard picked this height, not the learner, so the next open still uses
  /// the height they left it at (#7332, #7510). #8072.
  void _growForKeyboardIfNeeded() {
    if (!_cavityHasFocus || widget.keyboardInset <= 0) {
      _grewForKeyboard = false;
      return;
    }
    if (_grewForKeyboard ||
        widget.cavityChild == null ||
        _restState == NavCavityHeight.full) {
      return;
    }
    _grewForKeyboard = true;
    _openAt(NavCavityHeight.full, remember: false);
  }

  /// The fraction actually drawn this frame: derived from the rest state
  /// against the last-known max height, or the ad-hoc [_fraction] mid-drag.
  double get _currentFraction => switch (_restState) {
    null => _fraction,
    final rest => _fractionForState(rest, _lastMaxHeightPx),
  };

  NavCavityHeight _restoreHeight() {
    // Restore the height this cavity was left at. For a course (peek) cavity this
    // is what bridges a chat opening over it and closing: the widget is DISPOSED
    // then freshly mounted, and the static [_heightByKey] is the only survivor,
    // so the course reopens at the size the learner left it (#7332). A genuine
    // close FORGETS the entry ([didUpdateWidget]), so a fresh open with no stored
    // height falls back to the peek default — the deterministic entry state
    // (#7609). Section sheets read the same memory (#7510).
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
    // Dragging a SECTION sheet fully down is a dismissal, not a height
    // preference: collapsed renders 0px there (no handle left to grab), so
    // persisting it would make every reopen arrive already-dismissed and
    // stuck (#7510). The sheet still collapses now; the memory just keeps
    // the last real height for the reopen. A peek cavity's collapsed IS a
    // visible, draggable rest height (the 128px peek), so it is remembered
    // like any other — dragging a course down to peek and returning from a
    // chat must restore the peek, not a stale expanded height (#7332).
    if (height == NavCavityHeight.collapsed && !widget.cavityDefaultsToPeek) {
      return;
    }
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
        // Content-fit when the shell provided one: just tall enough to show
        // everything (a short chat list yields a short sheet), capped at the
        // max. The state keeps its name — it is still the default rest stop
        // between collapsed and full.
        final preferred = widget.preferredCavityHeightPx;
        if (preferred != null && maxHeightPx > 0) {
          return (preferred / maxHeightPx).clamp(0.1, 1.0);
        }
        return 0.5;
      case NavCavityHeight.full:
        return 1.0;
    }
  }

  // Resolved lazily against the current context in build(); stored here so
  // gesture callbacks (no BuildContext dependency) can reuse the last-known
  // value between frames.
  double _lastMaxHeightPx = 0.0;

  void _openAt(NavCavityHeight height, {bool remember = true}) {
    if (remember) _remember(height);
    _fullLatched = height == NavCavityHeight.full;
    setState(() => _restState = height);
  }

  /// Notify the shell of a latched full-height change AFTER the frame — calling
  /// back synchronously from build would `setState` the shell mid-build.
  void _syncFullReport() {
    if (_fullLatched == _reportedFull) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fullLatched == _reportedFull) return;
      _reportedFull = _fullLatched;
      widget.onCavityFullChanged?.call(_reportedFull);
    });
  }

  /// Handle tap: toggles half <-> full (the #7128 pattern) — reachable without
  /// a drag gesture for keyboard / switch access.
  void _toggleHandle() {
    final expanded = _currentFraction > 0.75;
    _openAt(expanded ? NavCavityHeight.half : NavCavityHeight.full);
  }

  void _onDragStart(DragStartDetails details) {
    // Leave the rest state: from here the fraction is the finger's.
    _fraction = _currentFraction;
    _restState = null;
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
    // Settle to the nearest of the three rest fractions (half is the
    // content-fit height when the shell provided one).
    final peek = widget.cavityDefaultsToPeek
        ? _peekFraction(_lastMaxHeightPx)
        : 0.0;
    final candidates = <NavCavityHeight, double>{
      NavCavityHeight.collapsed: peek,
      NavCavityHeight.half: _fractionForState(
        NavCavityHeight.half,
        _lastMaxHeightPx,
      ),
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
    // Dragging a dismiss-on-close sheet (the activity plan) fully down is a
    // CLOSE, not a collapse: the shell drops the token, which also clears the
    // map's activity focus (#7614). Peek cavities never take this branch —
    // their collapsed is a visible rest height, and the shell doesn't wire
    // [onDismissed] for them.
    if (nearest == NavCavityHeight.collapsed &&
        !widget.cavityDefaultsToPeek &&
        widget.onDismissed != null) {
      widget.onDismissed!();
      return;
    }
    _openAt(nearest);
  }

  /// Tapping outside the cavity — an ephemeral collapse, NOT a close: the
  /// shell's tokens stay, so re-expanding restores the same height. A
  /// dismiss-on-close sheet (the activity plan) instead closes outright: on
  /// narrow, tapping outside the sheet IS tapping the map, which clears the
  /// activity focus (#7614; world-map.instructions.md).
  void _collapseEphemeral() {
    final onDismissed = widget.onDismissed;
    if (onDismissed != null) {
      onDismissed();
      return;
    }
    _fullLatched = false;
    setState(() {
      _restState = null;
      _fraction = 0.0;
    });
  }

  /// Collapse an expanded cavity, or re-expand a collapsed one to its
  /// remembered height — the tap-the-active-item gesture.
  void _toggleCavity() {
    if (_currentFraction > 0.01) {
      _collapseEphemeral();
    } else {
      _openAt(_restoreHeight());
    }
  }

  void _onRailItemTap(AppSection section) {
    // Toggle only when the cavity is hosting THIS rail item's own surface
    // (the chat list for Chats, the hub for Courses) — NOT merely when the
    // item is highlighted. The highlight ([activeSection]) resolves a whole
    // course context to Courses, so with a course sheet hosted the Courses
    // icon looked active and this shortcut swallowed the tap that should
    // navigate to the hub (#7537).
    if (widget.cavityChild != null && section == widget.cavitySection) {
      _toggleCavity();
      return;
    }
    // Any other rail item: the shell handles token navigation and the next
    // build's didUpdateWidget resolves the resulting height.
    widget.onSectionTap(section);
  }

  Widget _withChatsBadge(Widget child) =>
      widget.chatsBadgeBuilder?.call(child) ?? child;

  void _onCourseShortcutTap() {
    // The shortcut's own toggle: when its course IS the hosted sheet, the tap
    // collapses/re-expands like any active rail item — a same-URL navigation
    // would be a visible no-op (#7537). Anything else navigates.
    if (widget.cavityChild != null && widget.courseShortcutHostsCavity) {
      _toggleCavity();
      return;
    }
    widget.onCourseShortcutTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeightPx = screenHeight * widget.maxHeightFraction;
    _lastMaxHeightPx = maxHeightPx;

    // The cavity's rest/drag height, WITHOUT the keyboard. This is the value
    // that animates on section snaps. The keyboard trim is applied separately,
    // instantly, in the builder below (#7754) — see [_cavityBox].
    final baseCavityPx = widget.cavityChild == null
        ? 0.0
        : (maxHeightPx * _currentFraction).clamp(0.0, maxHeightPx);

    final isExpanded = widget.cavityChild != null && _currentFraction > 0.01;

    // Report a settled full-height change up to the shell (post-frame).
    _syncFullReport();

    return Stack(
      children: [
        // Tap-outside barrier: only present while expanded, so it never
        // intercepts taps meant for whatever is behind the collapsed widget —
        // and never for a map-ground cavity ([mapStaysLive]), whose exposed
        // map must keep receiving taps/pans/pinches.
        if (isExpanded && !widget.mapStaysLive)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _collapseEphemeral,
              child: const SizedBox.expand(),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          // child: SafeArea(
          //   top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 12.0),
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
                          // Only `baseCavityPx` (the rest/drag height) drives
                          // the tween, so section snaps still animate. The
                          // keyboard inset is subtracted from the ANIMATED
                          // value inside the builder with a plain SizedBox —
                          // instant, in lockstep with the Scaffold's keyboard
                          // lift — so the widget's top never jumps up and
                          // readjusts when the keyboard opens (#7754).
                          TweenAnimationBuilder<double>(
                            duration: _animationDuration,
                            curve: Curves.easeOut,
                            tween: Tween<double>(end: baseCavityPx),
                            child: _NavCavity(
                              onHandleTap: _toggleHandle,
                              // At peek, a tap anywhere on the sheet (not
                              // claimed by an inner button) expands to full —
                              // the peek is an entry point, not a surface to
                              // interact with (#7609).
                              onBodyTap:
                                  widget.cavityDefaultsToPeek &&
                                      _restState == NavCavityHeight.collapsed
                                  ? () => _openAt(NavCavityHeight.full)
                                  : null,
                              onDragStart: _onDragStart,
                              onDragUpdate: _onDragUpdate,
                              onDragEnd: _onDragEnd,
                              // Watches the hosted surface for a focused text
                              // input (#8072). Focusable itself only as an
                              // ancestor — it never takes focus or a traversal
                              // stop of its own.
                              child: Focus(
                                canRequestFocus: false,
                                skipTraversal: true,
                                onFocusChange: _onCavityFocusChanged,
                                child: widget.cavityChild!,
                              ),
                            ),
                            builder: (context, animatedHeight, child) {
                              final trimmed =
                                  (animatedHeight - widget.keyboardInset).clamp(
                                    0.0,
                                    animatedHeight,
                                  );
                              // Hold the floor while the cavity holds focus, so
                              // the grow-to-full above has frames to run in
                              // without the trim unmounting the very field that
                              // triggered it (#8072).
                              final visible =
                                  _cavityHasFocus && baseCavityPx > 0
                                  ? max(
                                      trimmed,
                                      min(
                                        animatedHeight,
                                        _focusedKeyboardFloor,
                                      ),
                                    )
                                  : trimmed;
                              // Drop the content the instant the cavity is
                              // TARGETED shut (baseCavityPx), not when the
                              // ANIMATED height reaches 0 — otherwise a
                              // collapsing sheet squeezes its content into a
                              // few pixels mid-animation and the inner
                              // RenderFlex overflows.
                              final showContent =
                                  baseCavityPx > 0 && visible > 0;
                              return SizedBox(
                                key: _cavityBoxKey,
                                height: visible,
                                child: showContent
                                    ? ClipRect(child: child)
                                    : null,
                              );
                            },
                          ),
                        SizedBox(
                          height: _railHeight,
                          child: Semantics(
                            container: true,
                            label: l10n.navOptionsLabel,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                PangeaIconButton(
                                  selected:
                                      widget.activeSection == AppSection.world,
                                  tooltip: l10n.world,
                                  onPressed: () =>
                                      _onRailItemTap(AppSection.world),
                                ),
                                Semantics(
                                  container: true,
                                  selected:
                                      widget.activeSection == AppSection.chats,
                                  onTap: () => _onRailItemTap(AppSection.chats),
                                  child: _withChatsBadge(
                                    Tooltip(
                                      message: l10n.allChats,
                                      child: ExcludeSemantics(
                                        child: _RailButton(
                                          icon: Icons.forum_outlined,
                                          selectedIcon: Icons.forum,
                                          selected:
                                              widget.activeSection ==
                                              AppSection.chats,
                                          onTap: () =>
                                              _onRailItemTap(AppSection.chats),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                _RailButton(
                                  icon: Icons.map_outlined,
                                  selectedIcon: Icons.map,
                                  // The specific course's highlight (the
                                  // shortcut) outranks the section icon.
                                  selected:
                                      widget.activeSection ==
                                          AppSection.courses &&
                                      !widget.courseShortcutSelected,
                                  tooltip: l10n.courses,
                                  onTap: () =>
                                      _onRailItemTap(AppSection.courses),
                                ),
                                _CourseShortcutButton(
                                  icon: widget.courseShortcutIcon,
                                  label: widget.courseShortcutLabel,
                                  selected: widget.courseShortcutSelected,
                                  onTap: _onCourseShortcutTap,
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
        // ),
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
  final String? tooltip;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    this.tooltip,
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

  /// The shortcut's own course is the active workspace context — the mobile
  /// counterpart of the web rail highlighting the specific course avatar.
  final bool selected;

  const _CourseShortcutButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        // Announce the active-course state — the border alone is visual-only.
        selected: selected,
        // `container: true` forces the shortcut into its OWN standalone
        // semantics node instead of merging its tap + selected state up into
        // the rail's "Navigation options" node. The other three rail items are
        // IconButtons, which already stand alone; this custom InkWell did not,
        // so on Flutter web with the accessibility layer active (Firefox, and
        // release web builds generally) its tap dispatched to the merged rail
        // node and fell through to the live map behind — the course could be
        // collapsed but never re-expanded by tapping the shortcut (#7944; the
        // sibling web-semantics tap loss of #7927 / #7803). `label` gives the
        // now-standalone node its accessible name (the course), which it
        // previously borrowed from the merged rail node.
        container: true,
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(6.0),
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  )
                : null,
            margin: const EdgeInsets.all(2.0),
            child: icon ?? const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}

/// The expandable cavity: a drag handle (also a labeled toggle button, the
/// #7128 pattern) above the hosted section/course content, scrollable. The
/// content brings its own header/close.
class _NavCavity extends StatelessWidget {
  final VoidCallback onHandleTap;

  /// Non-null while the sheet rests at peek: a tap anywhere on the cavity not
  /// claimed by a deeper hitbox (the X, share, the progress-bar tooltip)
  /// expands the sheet. Null once expanded — the detector then only absorbs
  /// stray taps so they can't fall through to the map behind and deselect the
  /// course (#7609).
  final VoidCallback? onBodyTap;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final Widget child;

  const _NavCavity({
    required this.onHandleTap,
    required this.onBodyTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    // The whole cavity resizes by drag, not just the 36px handle — deeper
    // scrollables (an expanded tab's list) still win their own drags in the
    // gesture arena, so this only claims drags the content doesn't. Opaque so
    // the cavity is always a hit target: without it, taps on the sheet's dead
    // space fell through to the world map behind and deselected the course
    // (#7609).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onBodyTap,
      onVerticalDragStart: onDragStart,
      onVerticalDragUpdate: onDragUpdate,
      onVerticalDragEnd: onDragEnd,
      child: _cavityColumn(theme, l10n),
    );
  }

  Widget _cavityColumn(ThemeData theme, L10n l10n) {
    return Column(
      children: [
        // Grab handle: drag to resize, tap to toggle half/full. Exposed to
        // assistive tech as a single named button that runs the toggle (the
        // drag is pointer-only) — mirrors `MobileCourseSheet`'s handle (#7128).
        //
        // `container: true` forces the handle into its OWN semantics node
        // instead of merging into the cavity's node. It matters because the
        // enclosing cavity GestureDetector carries the vertical-drag (scroll)
        // actions but, for a non-peek cavity (the activity plan), NO tap of its
        // own (`onBodyTap` is null unless it's a course at peek). Without this,
        // the handle's tap action merged INTO that scrollable node, producing a
        // single node that was both scrollable and tappable. On Flutter web
        // with the accessibility layer active, pointer events dispatch through
        // the semantics DOM, and a scrollable node does not reliably deliver a
        // tap — so clicking the handle did nothing (only manual dragging
        // worked), but only on browsers/OSes that turn the a11y layer on
        // (#7927; the sibling web-semantics fall-through of #7803). A course at
        // peek was unaffected only because its cavity node had its own
        // `onBodyTap`, which kept the handle a separate child node. Forcing the
        // container makes the handle that separate button in every cavity.
        Semantics(
          container: true,
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
        // No header of its own: every cavity surface brings its own title and
        // close/back affordance (the chat list's and course card's panel
        // headers, the activity plan's contextual back/X — #7115), so the
        // cavity adds ONLY the handle. A second header here double-labelled
        // and double-X'd every surface (live QA).
        //
        // The child gets the BOUNDED cavity box directly — these are the same
        // WorkspaceLeftPanel surfaces the wide layout renders, and they own
        // their scrolling (the chat list's ListView, the hub's list, the
        // course card's per-tab scroll views). Wrapping them in an outer
        // scroll view hands them unbounded height and their internals
        // silently collapse to nothing (live QA: header-only empty panels).
        Expanded(child: child),
      ],
    );
  }
}
