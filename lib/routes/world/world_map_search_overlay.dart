import 'package:flutter/material.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';

/// Per-activity completion, derived client-side from Matrix session state.
/// Public so the map and this overlay share one vocabulary.
enum MapCompletionFilter { notStarted, inProgress, completed }

/// The Google-Maps-style search + filter surface floating over the World map.
/// Presentational: the map owns the pin set, the filter state, and the
/// filtering — this renders the bar/chips/results and reports user intent via
/// callbacks. World-only (the shell hides it elsewhere). See
/// world-map.instructions.md.
class WorldMapSearchOverlay extends StatefulWidget {
  final WorldMapFilter filter;

  final VoidCallback onReset;
  final VoidCallback onWidenSearch;

  final VoidCallback onToggleL2;
  final Function(String) updateQuery;
  final Function(LanguageLevelTypeEnum) toggleCefr;
  final Function(MapCompletionFilter) toggleCompletion;

  final List<QuestActivityCard> results;
  final Function(QuestActivityCard) onResultTap;

  final String? l2Label;
  final bool emptyInView;

  const WorldMapSearchOverlay({
    super.key,
    required this.filter,
    required this.updateQuery,
    required this.l2Label,
    required this.onToggleL2,
    required this.onWidenSearch,
    required this.toggleCefr,
    required this.toggleCompletion,
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
    final searching = widget.filter.query.trim().isNotEmpty;

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
            onChanged: widget.updateQuery,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surface,
              hintText: l10n.mapSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l10n.clearSearch,
                      onPressed: () => widget.updateQuery(''),
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
                  selected: widget.filter.l2Only,
                  label: Text(
                    widget.filter.l2Only
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
                    selected: widget.filter.cefrFilter.contains(level),
                    label: Text(level.string),
                    onSelected: (_) => widget.toggleCefr(level),
                  ),
                  const SizedBox(width: 6),
                ],
              for (final c in MapCompletionFilter.values) ...[
                FilterChip(
                  selected: widget.filter.completionFilter.contains(c),
                  label: Text(_completionLabel(l10n, c)),
                  onSelected: (_) => widget.toggleCompletion(c),
                ),
                const SizedBox(width: 6),
              ],
              if (widget.filter.canReset)
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
                  if (widget.filter.l2Only && widget.l2Label != null)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.translate, size: 16),
                      label: Text(l10n.widenSearch),
                      onPressed: widget.onWidenSearch,
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
