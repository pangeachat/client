import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

/// The single-column floating search bar riding above the nav widget
/// (routing.instructions.md → Single-column search bar): ONE persistent bar for
/// the WORLD map's activity search. It rides the nav widget's expansion for free
/// by rendering in the widget's `topAttachment` slot.
///
/// WORLD scope only — the shell mounts it over the bare world map and hides it
/// entirely on a course-scoped map (where the query does not filter pins) and
/// over a selected activity, mirroring the web overlay ([WorldMapSearchOverlay]),
/// which only renders in world scope.
///
/// The results list rides ABOVE the bar — the vertical mirror of the web
/// overlay, whose bar is at the top and whose results drop below it (on narrow
/// layouts the bar sits at the bottom of the screen, so results grow upward).
/// This gives narrow layouts the same returned list the web overlay has, so a
/// match that has been panned off-screen is still findable and tappable (a tap
/// flies the camera to it — the same action as tapping its pin).
///
/// Presentational: the shell decides the [hintText] (the scope) and where
/// [onQueryChanged] / [resultsBuilder] / [onResultTap] route. Map filter chips
/// ride ABOVE the bar via [filtersChild].
class MobileSearchBar extends StatefulWidget {
  /// The scope's hint ("Search activities"). Also the bar's semantic label, so
  /// assistive tech hears the scope.
  final String hintText;

  /// Externally-owned query for this scope; typing flows out through
  /// [onQueryChanged] and an external reset flows back in.
  final String query;

  final ValueChanged<String> onQueryChanged;

  /// The live result set for the current query — the map's `visiblePins`, the
  /// same list the web overlay renders. Read fresh on every (keystroke-driven)
  /// rebuild so the list tracks the query as it is typed. Null when this scope
  /// has no result list; the list only shows while the query is non-empty
  /// (matching the web overlay's dropdown).
  final List<QuestActivityCard> Function()? resultsBuilder;

  /// Fly the camera to a tapped result and open it (the same action as tapping
  /// its pin). Needed alongside [resultsBuilder] for the list to be tappable.
  final ValueChanged<QuestActivityCard>? onResultTap;

  /// Active map filter chips, rendered above the bar (map scope only).
  final Widget? filtersChild;

  const MobileSearchBar({
    required this.hintText,
    required this.query,
    required this.onQueryChanged,
    this.resultsBuilder,
    this.onResultTap,
    this.filtersChild,
    super.key,
  });

  @override
  State<MobileSearchBar> createState() => _MobileSearchBarState();
}

class _MobileSearchBarState extends State<MobileSearchBar> {
  /// Cap on how many results the list draws, matching the web overlay.
  static const _maxResults = 20;

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
    final l10n = L10n.of(context);

    // Drive the clear (X) button AND the results visibility off the field's own
    // controller, not the externally-owned query. This bar is built by the
    // shell, whose onQueryChanged reaches only the map's State (through a
    // GlobalKey), so a clear — or any programmatic query change — never rebuilds
    // this bar with a fresh widget.query. Reading the controller keeps both in
    // sync. See #7685.
    final searching = _controller.text.trim().isNotEmpty;

    final showResults = searching && widget.resultsBuilder != null;
    final results = showResults
        ? widget.resultsBuilder!()
        : const <QuestActivityCard>[];

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
          // The results list rides directly above the bar — the vertical mirror
          // of the web overlay's below-the-bar dropdown — shown only while a
          // query is present.
          if (showResults) ...[
            _ResultsList(
              results: results,
              maxResults: _maxResults,
              onResultTap: widget.onResultTap,
            ),
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
              // Rebuild so [searching] and the results list track the field as
              // the user types and backspaces — the shell doesn't rebuild this
              // bar per keystroke.
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

/// The returned-results dropdown for [MobileSearchBar], rendered above the bar.
/// The narrow-layout twin of [WorldMapSearchOverlay]'s results list: same star
/// row (title + `l2 · cefr`), same [_maxResults] cap, same empty-state copy.
class _ResultsList extends StatelessWidget {
  final List<QuestActivityCard> results;
  final int maxResults;
  final ValueChanged<QuestActivityCard>? onResultTap;

  const _ResultsList({
    required this.results,
    required this.maxResults,
    required this.onResultTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    // Cap the height so the floating list never climbs into the analytics bar or
    // off the top of the screen when the keyboard is open; it scrolls past the
    // cap. Measured against the space left above the keyboard, not the raw
    // viewport, so an open keyboard shrinks it too.
    final media = MediaQuery.of(context);
    final available = media.size.height - media.viewInsets.bottom;
    final maxHeight = math.min(320.0, available * 0.4);

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: results.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.mapSearchNoResults,
                  style: theme.textTheme.bodyMedium,
                ),
              )
            : Semantics(
                label: l10n.filteredActivitiesLabel,
                container: true,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: results.length > maxResults
                      ? maxResults
                      : results.length,
                  itemBuilder: (context, i) {
                    final card = results[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.star, size: 18),
                      title: Text(
                        card.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [card.l2, card.cefr]
                            .where((s) => s != null && s.isNotEmpty)
                            .join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: onResultTap == null
                          ? null
                          : () => onResultTap!(card),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
