import 'package:flutter/material.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// Per-activity completion, derived client-side from Matrix session state.
/// Public so the map and this overlay share one vocabulary.
enum MapCompletionFilter { notStarted, inProgress, completed }

/// The Google-Maps-style search + filter surface floating over the World map.
/// Presentational: the map owns the pin set, the filter state, and the
/// filtering — this renders the bar/chips/results and reports user intent via
/// callbacks. World-only (the shell hides it elsewhere). See
/// world-map.instructions.md.
class WorldMapSearchOverlay extends StatefulWidget {
  final String query;
  final ValueChanged<String> onQueryChanged;

  /// L2 chip: when true the map is scoped to the user's language ([l2Label]);
  /// toggling off widens to all languages (re-fetch).
  final bool l2Only;
  final String? l2Label;
  final VoidCallback onToggleL2;

  /// CEFR band: [selectedCefr] is the active level set (default = at/below the
  /// user's level); toggling a chip adds/removes a level.
  final Set<LanguageLevelTypeEnum> selectedCefr;
  final ValueChanged<LanguageLevelTypeEnum> onToggleCefr;

  final Set<MapCompletionFilter> selectedCompletion;
  final ValueChanged<MapCompletionFilter> onToggleCompletion;

  /// Live results for the current query (already filtered by the map). Shown as
  /// a dropdown only while the query is non-empty. Selecting flies to the pin.
  final List<QuestActivityCard> results;
  final ValueChanged<QuestActivityCard> onResultTap;

  /// True when any filter differs from the personalized default; drives the
  /// one-tap reset affordance.
  final bool canReset;
  final VoidCallback onReset;

  /// True when the current filters leave no pins in view; drives the inline
  /// widen affordance so personalization never dead-ends.
  final bool emptyInView;

  const WorldMapSearchOverlay({
    super.key,
    required this.query,
    required this.onQueryChanged,
    required this.l2Only,
    required this.l2Label,
    required this.onToggleL2,
    required this.selectedCefr,
    required this.onToggleCefr,
    required this.selectedCompletion,
    required this.onToggleCompletion,
    required this.results,
    required this.onResultTap,
    required this.canReset,
    required this.onReset,
    required this.emptyInView,
  });

  @override
  State<WorldMapSearchOverlay> createState() => _WorldMapSearchOverlayState();
}

class _WorldMapSearchOverlayState extends State<WorldMapSearchOverlay> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  static const _maxResults = 20;

  @override
  void didUpdateWidget(covariant WorldMapSearchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync only external query changes (reset / clear) into the field; normal
    // typing flows out through onQueryChanged and must not re-seat the cursor.
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _completionLabel(L10n l10n, MapCompletionFilter c) {
    switch (c) {
      case MapCompletionFilter.notStarted:
        return l10n.mapFilterNotStarted;
      case MapCompletionFilter.inProgress:
        return l10n.mapFilterInProgress;
      case MapCompletionFilter.completed:
        return l10n.mapFilterCompleted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final searching = widget.query.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(99),
          color: theme.colorScheme.surface,
          child: TextField(
            controller: _controller,
            onChanged: widget.onQueryChanged,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surface,
              hintText: l10n.mapSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l10n.close,
                      onPressed: () => widget.onQueryChanged(''),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(99),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (widget.l2Label != null) ...[
                FilterChip(
                  selected: widget.l2Only,
                  label: Text(
                    widget.l2Only
                        ? widget.l2Label!
                        : l10n.mapFilterAllLanguages,
                  ),
                  avatar: const Icon(Icons.translate, size: 16),
                  onSelected: (_) => widget.onToggleL2(),
                ),
                const SizedBox(width: 6),
              ],
              for (final level in LanguageLevelTypeEnum.values)
                if (level != LanguageLevelTypeEnum.preA1) ...[
                  FilterChip(
                    selected: widget.selectedCefr.contains(level),
                    label: Text(level.string),
                    onSelected: (_) => widget.onToggleCefr(level),
                  ),
                  const SizedBox(width: 6),
                ],
              for (final c in MapCompletionFilter.values) ...[
                FilterChip(
                  selected: widget.selectedCompletion.contains(c),
                  label: Text(_completionLabel(l10n, c)),
                  onSelected: (_) => widget.onToggleCompletion(c),
                ),
                const SizedBox(width: 6),
              ],
              if (widget.canReset)
                ActionChip(
                  avatar: const Icon(Icons.restart_alt, size: 16),
                  label: Text(l10n.mapFilterReset),
                  onPressed: widget.onReset,
                ),
            ],
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
                  : ListView.builder(
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
                  Text(l10n.mapEmptyInView, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  if (widget.l2Only && widget.l2Label != null)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.translate, size: 16),
                      label: Text(l10n.mapFilterAllLanguages),
                      onPressed: widget.onToggleL2,
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
