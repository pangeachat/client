import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_empty_view_card.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

/// The single-column floating search bar riding above the nav widget
/// (routing.instructions.md → Single-column search bar): ONE persistent bar for
/// the map's activity search. It rides the nav widget's expansion for free
/// by rendering in the widget's `topAttachment` slot.
///
/// Mounted over the bare map in BOTH scopes (#7716) — world and course alike,
/// mirroring the web overlay ([WorldMapSearchOverlay]) — and hidden entirely
/// over a selected activity or an open section sheet, which cover the exposed
/// map band it rides. On a course-scoped map it starts [minimized] to the
/// compact icon (routing.instructions.md → Single-column search bar).
///
/// Typing filters the map's pins live; there is no results dropdown on narrow —
/// the pins ARE the results. What rides above the bar instead (in addition to
/// the filter chips via [filtersChild]) is the verdict-driven empty-view card
/// ([WorldMapEmptyViewCard], the same one the web overlay shows): when the
/// view shows no matches it diagnoses WHY (off-screen matches, pill-excluded
/// matches, a dead query) and offers the one remedy that fixes it.
///
/// Presentational: the shell decides the [hintText] (the scope), the
/// [minimized] state, and where the callbacks route. State is read through
/// BUILDERS ([emptyVerdict], [canZoomOut]) re-evaluated on every local
/// rebuild, because this bar is shell-built and the map's own setState never
/// reaches it; [viewRevision]
/// (the map's filter/pin-load tick) triggers those rebuilds for changes that
/// don't originate here (a filter pill tap, a pin load after zooming out).
class MobileSearchBar extends StatefulWidget {
  /// The scope's hint ("Search activities"). Also the bar's semantic label, so
  /// assistive tech hears the scope.
  final String hintText;

  /// Externally-owned query for this scope; typing flows out through
  /// [onQueryChanged] and an external reset flows back in.
  final String query;

  final ValueChanged<String> onQueryChanged;

  /// The controller's diagnosis of why the view shows no matches
  /// ([WorldMapController.emptyVerdict]) — a builder re-read on every local
  /// rebuild; [MapEmptyVerdict.none] (or null: a scope without the card)
  /// renders nothing.
  final MapEmptyVerdict Function()? emptyVerdict;

  /// The camera is above its zoom-out floor — the card's Zoom out lever is
  /// live (greyed below it).
  final bool Function()? canZoomOut;

  /// The card's levers: clear every pill to "All …" / step the camera out one
  /// zoom level.
  final VoidCallback? onWidenSearch;
  final VoidCallback? onZoomOut;

  /// The map's "filtered view may have changed" tick
  /// ([WorldMapController.viewRevision]); each tick re-reads the builders.
  final Listenable? viewRevision;

  /// Active map filter chips, rendered above the bar (map scope only).
  final Widget? filtersChild;

  /// Compact-icon state: a single search icon button pinned left, restoring the
  /// full bar via [onRestore]. The course-scoped resting state
  /// (routing.instructions.md → Single-column search bar) — the scoped map's
  /// own chrome already owns the band, so search waits behind one tap. The
  /// empty-view card and filters stay hidden while minimized: they belong to
  /// the expanded bar.
  final bool minimized;
  final VoidCallback? onRestore;

  const MobileSearchBar({
    required this.hintText,
    required this.query,
    required this.onQueryChanged,
    this.minimized = false,
    this.onRestore,
    this.emptyVerdict,
    this.canZoomOut,
    this.onWidenSearch,
    this.onZoomOut,
    this.viewRevision,
    this.filtersChild,
    super.key,
  });

  @override
  State<MobileSearchBar> createState() => _MobileSearchBarState();
}

class _MobileSearchBarState extends State<MobileSearchBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void initState() {
    super.initState();
    widget.viewRevision?.addListener(_onViewRevision);
  }

  @override
  void didUpdateWidget(covariant MobileSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewRevision != widget.viewRevision) {
      oldWidget.viewRevision?.removeListener(_onViewRevision);
      widget.viewRevision?.addListener(_onViewRevision);
    }
    // Sync only external query changes (reset / scope switch) into the field;
    // normal typing flows out through onQueryChanged and must not re-seat the
    // cursor. Same contract as WorldMapSearchOverlay.
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    widget.viewRevision?.removeListener(_onViewRevision);
    _controller.dispose();
    super.dispose();
  }

  void _onViewRevision() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    if (widget.minimized) {
      // The compact state: one labeled icon button pinned to the left, just
      // above the nav rail; tapping restores the full bar.
      return Align(
        alignment: Alignment.centerLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(99),
          color: Theme.of(context).colorScheme.surface,
          child: IconButton(
            tooltip: widget.hintText,
            icon: const Icon(Icons.search),
            onPressed: widget.onRestore,
          ),
        ),
      );
    }

    // Drive the clear (X) button off the field's own controller, not the
    // externally-owned query. This bar is built by the shell, whose
    // onQueryChanged reaches only the map's State (through a GlobalKey), so a
    // clear — or any programmatic query change — never rebuilds this bar with
    // a fresh widget.query. Reading the controller keeps both in sync. See #7685.
    final searching = _controller.text.trim().isNotEmpty;

    final verdict = widget.emptyVerdict?.call() ?? MapEmptyVerdict.none;

    return Semantics(
      label: widget.hintText,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Narrow layout stacks bottom-up (field at the bottom, by the nav
          // rail): the message sits ABOVE the filters here — the reverse of the
          // web overlay, where the field leads and the filters/message pin
          // under it — so the diagnosis reads first, then the filters to act on.
          if (verdict != MapEmptyVerdict.none) ...[
            // Right-aligned (content-width), so it sits above the filter button
            // on the same right edge as the rest of the narrow chrome rather
            // than spanning from the far left.
            Align(
              alignment: Alignment.centerRight,
              child: WorldMapEmptyViewCard(
                verdict: verdict,
                canZoomOut: widget.canZoomOut?.call() ?? false,
                onWidenSearch: () => widget.onWidenSearch?.call(),
                onZoomOut: () => widget.onZoomOut?.call(),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.filtersChild != null) ...[
            widget.filtersChild!,
            const SizedBox(height: 8),
          ],
          // No Material wrapper here: PangeaSearchBar's own root is a Material
          // with the same elevation/radius/colour, so wrapping doubled the
          // floating bar's shadow.
          PangeaSearchBar(
            // The scope's hint, not a fixed one: the tooltip and Semantics label
            // above already read from it — a hardcoded label would disagree with
            // what assistive tech announces.
            labelText: widget.hintText,
            controller: _controller,
            onChanged: (value) {
              widget.onQueryChanged(value);
              // Rebuild so [searching] and the empty-view card track the field
              // as the user types and backspaces — the shell doesn't rebuild
              // this bar per keystroke.
              setState(() {});
            },
            suffixIcon: searching
                ? IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.clearSearch,
                    onPressed: () {
                      // Clear the field locally too: onQueryChanged only reaches
                      // the map's State, which won't rebuild this shell-built bar
                      // to sync the emptied query back in.
                      _controller.clear();
                      widget.onQueryChanged('');
                      setState(() {});
                    },
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
