import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_empty_view_card.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_filter_bar.dart';
import 'package:fluffychat/routes/world/world_map_level_fallback_notice.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/widgets/layouts/workspace_shell.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

/// Per-activity completion, derived client-side from Matrix session state.
/// Retained as the completion *derivation* (world-map.instructions.md,
/// "Filters") even though it is no longer a map filter — the Status pill
/// supersedes it. Still consumed by [WorldMapSignalUtils.reduceActivityCompletions].
enum MapCompletionFilter { notStarted, inProgress, completed }

/// The Google-Maps-style search + filter surface floating over the map.
/// Presentational: the map owns the pin set, the filter state, and the
/// filtering — this renders the bar, the [WorldMapFilterBar] pills, and the
/// results, reporting user intent via callbacks. Scope-agnostic: it rides the
/// world map and a course-scoped map alike (#7716), sized to whatever map
/// sliver the open panels leave. See world-map.instructions.md.
class WorldMapSearchOverlay extends StatefulWidget {
  final WorldMapFilter filter;

  final VoidCallback onReset;
  final VoidCallback onWidenSearch;

  final Function(String) updateQuery;

  /// The three filter pills: set the Level to exactly one CEFR level (null =
  /// All levels), Party size (null = All players), or Status (null = All
  /// statuses).
  final ValueChanged<LanguageLevelTypeEnum?> setCefrLevel;
  final ValueChanged<int?> setPartySize;
  final ValueChanged<ActivityPinState?> setStatus;

  final List<QuestActivityCard> results;
  final Function(QuestActivityCard) onResultTap;

  /// The controller's diagnosis of why the view shows no matches
  /// ([WorldMapController.emptyVerdict]) — drives the [WorldMapEmptyViewCard]
  /// whenever the results dropdown has no rows to offer instead.
  final MapEmptyVerdict emptyVerdict;

  /// The camera is above its zoom-out floor, so the card's Zoom out lever is
  /// live (greyed below it); [onZoomOut] resets to the whole-world view (all
  /// the way out, re-centered) — the map's World control.
  final bool canZoomOut;
  final VoidCallback onZoomOut;

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
    required this.emptyVerdict,
    required this.canZoomOut,
    required this.onZoomOut,
  });

  @override
  State<WorldMapSearchOverlay> createState() => _WorldMapSearchOverlayState();
}

class _WorldMapSearchOverlayState extends State<WorldMapSearchOverlay> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.filter.query,
  );

  /// The first dropdown row, so the down arrow can jump straight from the
  /// text field into the results (#8714) — the combobox pattern; without it a
  /// keyboard user must Tab through the filter pills to reach what they just
  /// searched for. Within the list the framework's default directional
  /// shortcuts take over, and Enter activates the focused row.
  final FocusNode _firstResultFocus = FocusNode(
    debugLabel: 'WorldMapSearchFirstResult',
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
    _firstResultFocus.dispose();
    super.dispose();
  }

  /// A single-line field has no caret use for the down arrow, so it is safe
  /// to repurpose as enter-the-results whenever rows are showing.
  KeyEventResult _onSearchBarKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent ||
        event.logicalKey != LogicalKeyboardKey.arrowDown ||
        !_firstResultFocus.canRequestFocus) {
      return KeyEventResult.ignored;
    }
    _firstResultFocus.requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final searching = widget.filter.query.trim().isNotEmpty;

    return Semantics(
      label: l10n.searchActivitiesLabel,
      // Keyed so the overlay slots between the cluster and the map's anchored
      // strip in the workspace browse order (#8755).
      sortKey: BrowseOrder.mapChrome,
      container: true,
      child: SafeArea(
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(
                onKeyEvent: _onSearchBarKey,
                // The interceptor rides the field's focus ancestry; the field
                // itself stays the Tab stop.
                canRequestFocus: false,
                skipTraversal: true,
                child: PangeaSearchBar(
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
              // The results dropdown renders only when it has rows; an empty
              // view — searching with no matches OR filters emptying the
              // viewport — shows the ONE unified card instead (formerly two
              // separate popups with a text-only no-matches state).
              if (searching && widget.results.isNotEmpty) ...[
                const SizedBox(height: 8),
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  color: theme.colorScheme.surface,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: Semantics(
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
                            focusNode: i == 0 ? _firstResultFocus : null,
                            dense: true,
                            leading: const Icon(Icons.star, size: 18),
                            title: Text(
                              card.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Semantics(
                              label:
                                  "${PLanguageStore.byLangCode(card.l2)?.displayName ?? card.l2}, ${card.cefr}",
                              child: ExcludeSemantics(
                                child: Text(
                                  [card.l2, card.cefr]
                                      .where((s) => s != null && s.isNotEmpty)
                                      .join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            onTap: () => widget.onResultTap(card),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ] else if (widget.emptyVerdict != MapEmptyVerdict.none) ...[
                const SizedBox(height: 8),
                WorldMapEmptyViewCard(
                  verdict: widget.emptyVerdict,
                  canZoomOut: widget.canZoomOut,
                  onWidenSearch: widget.onWidenSearch,
                  onZoomOut: widget.onZoomOut,
                ),
              ] else if (widget.filter.cefrFallback != null) ...[
                // Only once the map has something on it: an empty view is the
                // more urgent message and owns the slot when both apply.
                const SizedBox(height: 8),
                WorldMapLevelFallbackNotice(
                  selected: widget.filter.cefrLevel,
                  fallback: widget.filter.cefrFallback,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
