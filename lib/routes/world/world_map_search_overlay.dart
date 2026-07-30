import 'package:flutter/material.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_filter_bar.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

/// Per-activity completion, derived client-side from Matrix session state.
/// Retained as the completion *derivation* (world-map.instructions.md,
/// "Filters") even though it is no longer a map filter — the Status pill
/// supersedes it. Still consumed by [WorldMapSignalUtils.reduceActivityCompletions].
enum MapCompletionFilter { notStarted, inProgress, completed }

/// The Google-Maps-style search + filter surface floating over the World map.
/// Presentational: the map owns the pin set, the filter state, and the
/// filtering — this renders the bar, the [WorldMapFilterBar] pills, and the
/// results, reporting user intent via callbacks. World-only (the shell hides it
/// elsewhere). See world-map.instructions.md.
class WorldMapSearchOverlay extends StatefulWidget {
  final WorldMapFilter filter;

  final VoidCallback onReset;
  final VoidCallback onWidenSearch;

  final Function(String) updateQuery;

  /// The three filter pills: set the Level ceiling (null = All levels), Party
  /// size (null = All players), or Status (null = All statuses).
  final ValueChanged<LanguageLevelTypeEnum?> setCefrLevel;
  final ValueChanged<MapPartySize?> setPartySize;
  final ValueChanged<ActivityPinState?> setStatus;

  final List<QuestActivityCard> results;
  final Function(QuestActivityCard) onResultTap;

  final bool emptyInView;

  const WorldMapSearchOverlay({
    super.key,
    required this.filter,
    required this.updateQuery,
    required this.onWidenSearch,
    required this.setCefrLevel,
    required this.setPartySize,
    required this.setStatus,
    required this.results,
    required this.onResultTap,
    required this.onReset,
    required this.emptyInView,
  });

  @override
  State<WorldMapSearchOverlay> createState() => _WorldMapSearchOverlayState();
}

class _WorldMapSearchOverlayState extends State<WorldMapSearchOverlay> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.filter.query,
  );

  static const _maxResults = 20;

  @override
  void didUpdateWidget(covariant WorldMapSearchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync only external query changes (reset / clear) into the field; normal
    // typing flows out through onQueryChanged and must not re-seat the cursor.
    if (widget.filter.query != _controller.text) {
      _controller.text = widget.filter.query;
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
    final searching = widget.filter.query.trim().isNotEmpty;

    return Semantics(
      label: l10n.searchActivitiesLabel,
      container: true,
      child: SafeArea(
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              PangeaSearchBar(
                controller: _controller,
                onChanged: widget.updateQuery,
                labelText: l10n.mapSearchHint,
                suffixIcon: searching
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: l10n.clearSearch,
                        onPressed: () => widget.updateQuery(''),
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              Semantics(
                label: l10n.activityFilterButtonsLabel,
                container: true,
                child: WorldMapFilterBar(
                  filter: widget.filter,
                  onSetLevel: widget.setCefrLevel,
                  onSetPartySize: widget.setPartySize,
                  onSetStatus: widget.setStatus,
                  onReset: widget.onReset,
                ),
              ),
              if (searching) ...[
                const SizedBox(height: 8),
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  color: theme.colorScheme.surface,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: widget.results.isEmpty
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
                              itemCount: widget.results.length > _maxResults
                                  ? _maxResults
                                  : widget.results.length,
                              itemBuilder: (context, i) {
                                final card = widget.results[i];
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
                                  onTap: () => widget.onResultTap(card),
                                );
                              },
                            ),
                          ),
                  ),
                ),
              ] else if (widget.emptyInView) ...[
                const SizedBox(height: 8),
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  color: theme.colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.mapEmptyInView,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        // Language is fixed by settings, so the only in-app widen
                        // lever is broadening the level band to All levels (zoom
                        // out is the other, via the map controls). Offered only
                        // when a level filter is actually narrowing the view.
                        if (widget.filter.cefrFilter.isNotEmpty)
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.filter_alt_off, size: 16),
                            label: Text(l10n.widenSearch),
                            onPressed: widget.onWidenSearch,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
