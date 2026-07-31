import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_filter_bar.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The single-column (narrow-layout) home for the world-map filters, riding the
/// search bar's `filtersChild` slot. A constant filter bar crowds the narrow
/// map, so it lives collapsed by default — a small filter button pinned to the
/// right with a badge counting how many categories are narrowed off "All"
/// ([WorldMapFilter.activeFilterCount], one by default: the level) — and expands
/// to the full [WorldMapFilterBar] on tap so the learner can change as many
/// pills as they like. It folds back to the button the moment they pan the map
/// (the [collapseSignal] tick) or tap the toggle. The wide layout keeps its
/// filter bar always open, so this collapse/expand shell is narrow-layout only.
///
/// Presentational, like [WorldMapFilterBar]: [filterBuilder] reads the live
/// filter each build and the pills report intent through the same controller
/// callbacks the wide overlay uses.
class WorldMapMobileFilters extends StatefulWidget {
  /// Reads the live filter on every build. A getter, not a snapshot: a pill tap
  /// mutates the map's own State, which does not rebuild this shell-built widget,
  /// so it must pull the fresh filter itself after each change — the same
  /// contract as `resultsBuilder` on the search bar it rides.
  final WorldMapFilter Function() filterBuilder;

  /// The three pills, wired to the controller exactly as the wide overlay wires
  /// them: null clears a category to its "All …" state.
  final ValueChanged<LanguageLevelTypeEnum?> onSetLevel;
  final ValueChanged<MapPartySize?> onSetPartySize;
  final ValueChanged<ActivityPinState?> onSetStatus;
  final VoidCallback onReset;

  /// Ticks when the learner pans/pinches the map
  /// ([WorldMapController.mapPanTick]); each tick collapses an open bar.
  final Listenable collapseSignal;

  const WorldMapMobileFilters({
    super.key,
    required this.filterBuilder,
    required this.onSetLevel,
    required this.onSetPartySize,
    required this.onSetStatus,
    required this.onReset,
    required this.collapseSignal,
  });

  @override
  State<WorldMapMobileFilters> createState() => _WorldMapMobileFiltersState();
}

class _WorldMapMobileFiltersState extends State<WorldMapMobileFilters> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    widget.collapseSignal.addListener(_collapse);
  }

  @override
  void didUpdateWidget(covariant WorldMapMobileFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapseSignal != widget.collapseSignal) {
      oldWidget.collapseSignal.removeListener(_collapse);
      widget.collapseSignal.addListener(_collapse);
    }
  }

  @override
  void dispose() {
    widget.collapseSignal.removeListener(_collapse);
    super.dispose();
  }

  /// Fold back to the button when the map is panned — but only touch state while
  /// actually open, so the per-frame pan ticks don't churn setState.
  void _collapse() {
    if (_expanded && mounted) setState(() => _expanded = false);
  }

  /// Re-read the live filter after a pill change so the badge count and pill
  /// fills track the new state (the map's own setState does not reach here).
  void _onChanged(VoidCallback apply) {
    apply();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final filter = widget.filterBuilder();

    if (!_expanded) {
      return Align(
        alignment: Alignment.centerRight,
        child: _FilterIconButton(
          tooltip: l10n.mapFiltersShow,
          badgeCount: filter.activeFilterCount,
          active: false,
          onTap: () => setState(() => _expanded = true),
        ),
      );
    }

    return Semantics(
      label: l10n.activityFilterButtonsLabel,
      container: true,
      child: Row(
        children: [
          _FilterIconButton(
            tooltip: l10n.mapFiltersHide,
            active: true,
            onTap: () => setState(() => _expanded = false),
          ),
          const SizedBox(width: 6),
          // The full pill row (reused from the wide overlay), given bounded width
          // so its own horizontal scroll absorbs overflow on a narrow screen.
          Expanded(
            child: WorldMapFilterBar(
              filter: filter,
              onSetLevel: (v) => _onChanged(() => widget.onSetLevel(v)),
              onSetPartySize: (v) => _onChanged(() => widget.onSetPartySize(v)),
              onSetStatus: (v) => _onChanged(() => widget.onSetStatus(v)),
              onReset: () => _onChanged(widget.onReset),
            ),
          ),
        ],
      ),
    );
  }
}

/// The round filter affordance shared by both states: the collapsed button (with
/// a [badgeCount] bubble at its top-right) and the expanded bar's leading toggle
/// ([active], filled to read as "open — tap to close"). Styled like the filter
/// pills — a plain surface pill, or a filled primary-container one.
class _FilterIconButton extends StatelessWidget {
  final String tooltip;
  final bool active;
  final int badgeCount;
  final VoidCallback onTap;

  const _FilterIconButton({
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = active ? scheme.primaryContainer : scheme.surface;
    final fg = active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    final button = Material(
      color: bg,
      elevation: 2,
      shape: CircleBorder(
        side: BorderSide(
          color: active ? Colors.transparent : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(Icons.filter_alt, size: 20, color: fg),
        ),
      ),
    );

    return Tooltip(
      message: tooltip,
      child: Badge(
        isLabelVisible: badgeCount > 0,
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
        label: Text('$badgeCount'),
        child: button,
      ),
    );
  }
}
