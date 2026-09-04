import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The world-map filter row: one dropdown-pill per category (Level, Party size,
/// Status), each defaulting to "All …" (no narrowing) and set via its dropdown
/// rather than toggled — plus a trailing reset control that appears whenever any
/// pill differs from that default, i.e. whenever any is off "All"
/// (world-map.instructions.md, "Filters"). Presentational: it renders [filter]
/// and reports intent through the
/// callbacks; the controller owns the state. Language is deliberately NOT a pill
/// (it is fixed by the learner's settings).
class WorldMapFilterBar extends StatelessWidget {
  final WorldMapFilter filter;

  /// Set the Level to exactly one CEFR level (null = All levels), Party size
  /// (null = All players), or Status (null = All statuses); [onReset] restores
  /// every pill at once.
  final ValueChanged<LanguageLevelTypeEnum?> onSetLevel;
  final ValueChanged<int?> onSetPartySize;
  final ValueChanged<ActivityPinState?> onSetStatus;
  final VoidCallback onReset;

  /// Anchor the pills to the right of the scroll viewport
  final bool reverse;

  const WorldMapFilterBar({
    super.key,
    required this.filter,
    required this.onSetLevel,
    required this.onSetPartySize,
    required this.onSetStatus,
    required this.onReset,
    this.reverse = false,
  });

  /// The CEFR levels offered — Pre-A1 through C2. Picking one filters to exactly
  /// that level (not a band).
  static const _levelOptions = [
    LanguageLevelTypeEnum.preA1,
    LanguageLevelTypeEnum.a1,
    LanguageLevelTypeEnum.a2,
    LanguageLevelTypeEnum.b1,
    LanguageLevelTypeEnum.b2,
    LanguageLevelTypeEnum.c1,
    LanguageLevelTypeEnum.c2,
  ];

  /// Status options in display order (world-map.instructions.md): Available,
  /// Ongoing, Open to Join, Waiting, Completed.
  static const _statusOptions = [
    ActivityPinState.available,
    ActivityPinState.ongoingActive,
    ActivityPinState.joinable,
    ActivityPinState.ongoingPending,
    ActivityPinState.inProgress,
  ];

  String _statusLabel(BuildContext context, ActivityPinState s) {
    final l10n = L10n.of(context);
    return switch (s) {
      ActivityPinState.available => l10n.mapStatusAvailable,
      ActivityPinState.ongoingActive => l10n.mapStatusOngoing,
      ActivityPinState.joinable => l10n.mapStatusOpenToJoin,
      ActivityPinState.ongoingPending => l10n.mapStatusWaiting,
      ActivityPinState.inProgress => l10n.mapFilterCompleted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final level = filter.cefrLevel;
    const groups = Icon(Icons.groups);

    final levelEntries = <_FilterMenuEntry>[
      _FilterMenuEntry(
        label: l10n.mapFilterAllLevels,
        selected: filter.cefrFilter.isEmpty,
        onSelected: () => onSetLevel(null),
      ),
      for (final lvl in _levelOptions)
        _FilterMenuEntry(
          label: lvl.title(context),
          selected: level == lvl,
          onSelected: () => onSetLevel(lvl),
        ),
    ];

    final partyEntries = <_FilterMenuEntry>[
      _FilterMenuEntry(
        label: l10n.mapFilterAllPlayers,
        selected: filter.partySize == null,
        onSelected: () => onSetPartySize(null),
      ),
      for (final p in WorldMapFilter.partySizeOptions)
        _FilterMenuEntry(
          label: l10n.mapFilterPlayerCount(p),
          selected: filter.partySize == p,
          onSelected: () => onSetPartySize(p),
        ),
    ];

    final statusEntries = <_FilterMenuEntry>[
      _FilterMenuEntry(
        label: l10n.mapFilterAllStatuses,
        selected: filter.status == null,
        onSelected: () => onSetStatus(null),
      ),
      for (final s in _statusOptions)
        _FilterMenuEntry(
          label: _statusLabel(context, s),
          selected: filter.status == s,
          onSelected: () => onSetStatus(s),
          icon: s.icon,
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: reverse,
      child: Row(
        children: [
          _FilterDropdownPill(
            label: level == null ? l10n.mapFilterAllLevels : level.shortLabel,
            active: filter.cefrFilter.isNotEmpty,
            entries: levelEntries,
          ),
          const SizedBox(width: 6),
          _FilterDropdownPill(
            label: filter.partySize == null
                ? l10n.mapFilterAllPlayers
                : '${filter.partySize}',
            icon: groups,
            active: filter.partySize != null,
            entries: partyEntries,
          ),
          const SizedBox(width: 6),
          _FilterDropdownPill(
            label: filter.status == null
                ? l10n.mapFilterAllStatuses
                : _statusLabel(context, filter.status!),
            icon: filter.status != null ? Icon(filter.status!.icon) : null,
            active: filter.status != null,
            entries: statusEntries,
          ),
          // Reset lives at the END of the row, styled like an off/white pill;
          // it appears only when a filter differs from its default.
          if (filter.canReset) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.refresh),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              tooltip: l10n.mapFilterReset,
              onPressed: onReset,
              style: IconButton.styleFrom(
                backgroundColor: scheme.surface,
                foregroundColor: scheme.onSurfaceVariant,
                side: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One option in a filter pill's dropdown: its [label], whether it is the current
/// [selected] value (shown with a check), and the [onSelected] action.
class _FilterMenuEntry {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  /// An optional leading glyph — the status entries carry their
  /// [ActivityPinState.icon] so the dropdown matches the map pins.
  final IconData? icon;
  const _FilterMenuEntry({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });
}

/// A single filter category rendered as a pill that opens its option [entries]
/// in a dropdown anchored beneath it. [active] (a specific value is selected)
/// fills the pill light-purple with a leading check; otherwise it is a plain
/// white "All …" pill. [icon] is an optional category glyph shown on the pill
/// when active (the party-size people icon).
///
/// Built on [MenuAnchor] + [MenuItemButton] rather than PopupMenuButton
/// (#8724 review): the popup-menu route opened without moving focus into the
/// menu, leaving a keyboard or VoiceOver user no visible way to reach its
/// items or close it. Here the first item takes focus the moment the menu
/// opens, arrows rove the items, Enter selects, and Escape closes with focus
/// returned to the pill. The pill itself is a [FocusRingTapTarget], which
/// also gives it the gold focus ring PopupMenuButton's opaque child swallowed.
class _FilterDropdownPill extends StatefulWidget {
  final String label;
  final Widget? icon;
  final bool active;
  final List<_FilterMenuEntry> entries;

  const _FilterDropdownPill({
    required this.label,
    this.icon,
    required this.active,
    required this.entries,
  });

  @override
  State<_FilterDropdownPill> createState() => _FilterDropdownPillState();
}

class _FilterDropdownPillState extends State<_FilterDropdownPill> {
  final MenuController _menuController = MenuController();

  /// The pill's focus node, handed to [MenuAnchor.childFocusNode] so closing
  /// the menu (Escape, or selecting an item) returns focus to the pill.
  final FocusNode _buttonFocusNode = FocusNode(debugLabel: 'FilterPill');

  @override
  void dispose() {
    _buttonFocusNode.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuController.isOpen) {
      _menuController.close();
    } else {
      _menuController.open();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = widget.active ? scheme.primaryContainer : scheme.surface;
    final fg = widget.active
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return MenuAnchor(
      controller: _menuController,
      childFocusNode: _buttonFocusNode,
      menuChildren: [
        for (final e in widget.entries)
          MenuItemButton(
            // Focus lands on the first item as the menu opens, so a keyboard
            // or screen-reader user is IN the menu immediately — arrows move,
            // Enter selects, Escape closes (#8724 review).
            autofocus: e == widget.entries.first,
            onPressed: e.onSelected,
            child: ConstrainedBox(
              // Bound the row so a label longer than the old popup-menu's max
              // width (the ACTFL level titles, long translations) wraps
              // instead of stretching the menu.
              constraints: const BoxConstraints(maxWidth: 260),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    child: e.selected
                        ? Icon(Icons.check, size: 18, color: scheme.primary)
                        : null,
                  ),
                  if (e.icon != null) ...[
                    Icon(e.icon, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: Text(e.label)),
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, child) => FocusRingTapTarget(
        onTap: _toggleMenu,
        focusNode: _buttonFocusNode,
        shape: const StadiumBorder(),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: widget.active ? Colors.transparent : scheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.active) ...[
                Icon(Icons.check, size: 16, color: fg),
                const SizedBox(width: 4),
              ],
              if (widget.icon != null) ...[
                IconTheme.merge(
                  data: IconThemeData(size: 16, color: fg),
                  child: widget.icon!,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                widget.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
