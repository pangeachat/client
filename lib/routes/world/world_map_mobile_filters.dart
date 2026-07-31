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
/// ([WorldMapFilter.activeFilterCount], **zero by default**: every pill starts
/// at "All", so no badge shows until the learner narrows one) — and the
/// full [WorldMapFilterBar] animates open leftward FROM that button on tap
/// (the button stays put and fills purple), so the learner can change as many
/// pills as they like. It folds back to the button the moment they pan the map
/// (the [collapseSignal] tick) or tap the toggle. The wide layout keeps its
/// filter bar always open, so this collapse/expand shell is narrow-layout only.
///
/// Presentational, like [WorldMapFilterBar]: [filterBuilder] reads the live
/// filter each build and the pills report intent through the same controller
/// callbacks the wide overlay uses.
class WorldMapMobileFilters extends StatefulWidget {
  /// Reads the live filter on every build. A getter, not a snapshot: a filter
  /// mutation updates the map's own State, which does not rebuild this
  /// shell-built widget, so it must pull the fresh filter itself after each
  /// change.
  final WorldMapFilter Function() filterBuilder;

  /// Ticks whenever the filter changes ([WorldMapController.viewRevision]),
  /// including mutations that do NOT originate from this bar's own pills — the
  /// empty card's "Widen search", a reset, a settings-driven level change.
  final Listenable filterRevision;

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
    required this.filterRevision,
  });

  @override
  State<WorldMapMobileFilters> createState() => _WorldMapMobileFiltersState();
}

class _WorldMapMobileFiltersState extends State<WorldMapMobileFilters>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _slide = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  @override
  void initState() {
    super.initState();
    widget.collapseSignal.addListener(_collapse);
    widget.filterRevision.addListener(_onFilterRevision);
  }

  @override
  void didUpdateWidget(covariant WorldMapMobileFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapseSignal != widget.collapseSignal) {
      oldWidget.collapseSignal.removeListener(_collapse);
      widget.collapseSignal.addListener(_collapse);
    }
    if (oldWidget.filterRevision != widget.filterRevision) {
      oldWidget.filterRevision.removeListener(_onFilterRevision);
      widget.filterRevision.addListener(_onFilterRevision);
    }
  }

  @override
  void dispose() {
    widget.collapseSignal.removeListener(_collapse);
    widget.filterRevision.removeListener(_onFilterRevision);
    _anim.dispose();
    super.dispose();
  }

  void _onFilterRevision() {
    if (mounted) setState(() {});
  }

  void _setExpanded(bool expanded) {
    if (_expanded == expanded) return;
    setState(() => _expanded = expanded);
    expanded ? _anim.forward() : _anim.reverse();
  }

  /// Fold back to the button when the map is panned — but only touch state while
  /// actually open, so the per-frame pan ticks don't churn setState.
  void _collapse() {
    if (_expanded && mounted) _setExpanded(false);
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

    return Semantics(
      label: l10n.activityFilterButtonsLabel,
      container: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The pills fill the width left of the fixed button (40) and its gap
          // (6), scrolling horizontally if they overflow it.
          final pillWidth = (constraints.maxWidth - _buttonSlot - 6).clamp(
            0.0,
            double.infinity,
          );
          // Built once per (setState) rebuild — NOT per animation tick.
          final pills = SizedBox(
            width: pillWidth,
            child: WorldMapFilterBar(
              filter: filter,
              reverse: true,
              onSetLevel: (v) => _onChanged(() => widget.onSetLevel(v)),
              onSetPartySize: (v) => _onChanged(() => widget.onSetPartySize(v)),
              onSetStatus: (v) => _onChanged(() => widget.onSetStatus(v)),
              onReset: () => _onChanged(widget.onReset),
            ),
          );
          return AnimatedBuilder(
            animation: _slide,
            child: pills,
            builder: (context, child) {
              final t = _slide.value;
              final open = t > 0;
              return Row(
                // The button is pinned to the RIGHT in both states, so it
                // never jumps sides; the pills slide out to its left and back.
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // A fixed-size window the pills TRANSLATE through: at t=0 they
                  // sit fully off to the right (hidden under the button), at
                  // t=1 they fill it — a slide, at constant height, with no
                  // resize-clip. Omitted entirely once fully closed so the pill
                  // bar leaves the tree (and its semantics with it).
                  if (open)
                    Listener(
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: pillWidth,
                          child: ClipRect(
                            child: FractionalTranslation(
                              translation: Offset(1 - t, 0),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  _FilterIconButton(
                    tooltip: open ? l10n.mapFiltersHide : l10n.mapFiltersShow,
                    // Filled purple while open (holds through the slide out); a
                    // plain pill once closed, where the badge carries the count.
                    active: open,
                    badgeCount: open ? 0 : filter.activeFilterCount,
                    onTap: () => _setExpanded(!_expanded),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

const double _buttonSlot = 40;

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
