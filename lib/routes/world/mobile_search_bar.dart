import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

/// The single-column floating search bar riding above the nav widget
/// (routing.instructions.md → Single-column search bar): ONE persistent bar
/// whose scope follows what is open — the activity search over the bare map,
/// the chat list or the courses list when that section is expanded. It rides
/// the nav widget's expansion for free by rendering in the widget's
/// `topAttachment` slot.
///
/// Presentational: the shell decides the [hintText] (the scope), the
/// [minimized] state (map scroll / a bare course-scoped map — an expanded
/// section always wins and shows the bar), and where [onQueryChanged] routes.
/// Map filter chips ride ABOVE the bar via [filtersChild] and minimize with it.
class MobileSearchBar extends StatefulWidget {
  /// The scope's hint ("Search Pangea", "Search All chats", "Search Courses").
  /// Also the bar's semantic label, so assistive tech hears the scope.
  final String hintText;

  /// Externally-owned query for this scope; typing flows out through
  /// [onQueryChanged] and an external reset flows back in.
  final String query;

  final ValueChanged<String> onQueryChanged;

  /// Compact-icon state: a single search icon button pinned left, restoring
  /// the full bar via [onRestore].
  final bool minimized;

  final VoidCallback? onRestore;

  /// Active map filter chips, rendered above the bar (map scope only).
  final Widget? filtersChild;

  const MobileSearchBar({
    required this.hintText,
    required this.query,
    required this.onQueryChanged,
    this.minimized = false,
    this.onRestore,
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
  void didUpdateWidget(covariant MobileSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync only external query changes (reset / scope switch) into the field;
    // normal typing flows out through onQueryChanged and must not re-seat the
    // cursor. Same contract as WorldMapSearchOverlay.
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    if (widget.minimized) {
      // The compact state: one labeled icon button pinned to the left, just
      // above the nav rail; tapping restores the full bar.
      return Align(
        alignment: Alignment.centerLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(99),
          color: theme.colorScheme.surface,
          child: IconButton(
            tooltip: widget.hintText,
            icon: const Icon(Icons.search),
            onPressed: widget.onRestore,
          ),
        ),
      );
    }

    // Drive the clear (X) button off the field's own controller, not the
    // externally-owned query. This single-column bar is built by the shell, but
    // its onQueryChanged reaches only the map's State (through a GlobalKey), so
    // a clear — or any programmatic query change — never rebuilds this bar with
    // a fresh widget.query. Reading the controller keeps it in sync. See #7685.
    final searching = _controller.text.trim().isNotEmpty;
    return Semantics(
      label: widget.hintText,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.filtersChild != null) ...[
            widget.filtersChild!,
            const SizedBox(height: 8),
          ],
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(99),
            color: theme.colorScheme.surface,
            child: PangeaSearchBar(
              labelText: L10n.of(context).searchActivitiesHint,
              controller: _controller,
              onChanged: (value) {
                widget.onQueryChanged(value);
                // Rebuild so [searching] tracks the field as the user types and
                // backspaces — the shell doesn't rebuild this bar per keystroke.
                setState(() {});
              },
              suffixIcon: searching
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l10n.clearSearch,
                      onPressed: () {
                        // Clear the field locally too: onQueryChanged only
                        // reaches the map's State, which won't rebuild this
                        // shell-built bar to sync the emptied query back in.
                        _controller.clear();
                        widget.onQueryChanged('');
                        setState(() {});
                      },
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
