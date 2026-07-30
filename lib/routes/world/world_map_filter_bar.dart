import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The world-map filter row: one dropdown-pill per category (Level, Party size,
/// Status), each pre-seeded to its default and cleared via an "All …" option
/// rather than toggled off — plus a leading reset control that appears whenever
/// any pill differs from its personalized default (world-map.instructions.md,
/// "Filters"). Presentational: it renders [filter] and reports intent through the
/// callbacks; the controller owns the state. Language is deliberately NOT a pill
/// (it is fixed by the learner's settings).
class WorldMapFilterBar extends StatelessWidget {
  final WorldMapFilter filter;

  /// Set the Level ceiling (null = All levels), Party size (null = All players),
  /// or Status (null = All statuses); [onReset] restores every pill at once.
  final ValueChanged<LanguageLevelTypeEnum?> onSetLevel;
  final ValueChanged<MapPartySize?> onSetPartySize;
  final ValueChanged<ActivityPinState?> onSetStatus;
  final VoidCallback onReset;

  const WorldMapFilterBar({
    super.key,
    required this.filter,
    required this.onSetLevel,
    required this.onSetPartySize,
    required this.onSetStatus,
    required this.onReset,
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

  // A short pill/dropdown label for a level — the CEFR code (Pre-A1 spelled
  // prettily). Picking a level filters to exactly that level.
  String _levelLabel(LanguageLevelTypeEnum lvl) =>
      lvl == LanguageLevelTypeEnum.preA1 ? 'Pre-A1' : lvl.string;

  String _partyLabel(MapPartySize p) => switch (p) {
    MapPartySize.two => '2',
    MapPartySize.three => '3',
    MapPartySize.fourPlus => '4+',
  };

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
          label: _levelLabel(lvl),
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
      for (final p in MapPartySize.values)
        _FilterMenuEntry(
          label: _partyLabel(p),
          leading: groups,
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
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterDropdownPill(
            label: level == null
                ? l10n.mapFilterAllLevels
                : _levelLabel(level),
            active: filter.cefrFilter.isNotEmpty,
            entries: levelEntries,
          ),
          const SizedBox(width: 6),
          _FilterDropdownPill(
            label: filter.partySize == null
                ? l10n.mapFilterAllPlayers
                : _partyLabel(filter.partySize!),
            icon: groups,
            active: filter.partySize != null,
            entries: partyEntries,
          ),
          const SizedBox(width: 6),
          _FilterDropdownPill(
            label: filter.status == null
                ? l10n.mapFilterAllStatuses
                : _statusLabel(context, filter.status!),
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

/// One option in a filter pill's dropdown: its [label], an optional [leading]
/// glyph (the people icon for party sizes), whether it is the current
/// [selected] value (shown with a check), and the [onSelected] action.
class _FilterMenuEntry {
  final String label;
  final Widget? leading;
  final bool selected;
  final VoidCallback onSelected;
  const _FilterMenuEntry({
    required this.label,
    this.leading,
    required this.selected,
    required this.onSelected,
  });
}

/// A single filter category rendered as a pill that opens its option [entries]
/// in a dropdown anchored beneath it. [active] (a specific value is selected)
/// fills the pill light-purple with a leading check; otherwise it is a plain
/// white "All …" pill. [icon] is an optional category glyph shown on the pill
/// when active (the party-size people icon).
class _FilterDropdownPill extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = active ? scheme.primaryContainer : scheme.surface;
    final fg = active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    return PopupMenuButton<_FilterMenuEntry>(
      tooltip: label,
      position: PopupMenuPosition.under,
      onSelected: (e) => e.onSelected(),
      itemBuilder: (context) => [
        for (final e in entries)
          PopupMenuItem<_FilterMenuEntry>(
            value: e,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: e.selected
                      ? Icon(Icons.check, size: 18, color: scheme.primary)
                      : null,
                ),
                if (e.leading != null) ...[
                  IconTheme.merge(
                    data: const IconThemeData(size: 16),
                    child: e.leading!,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(e.label),
              ],
            ),
          ),
      ],
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: active ? Colors.transparent : scheme.outlineVariant,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) ...[
              Icon(Icons.check, size: 16, color: fg),
              const SizedBox(width: 4),
            ],
            if (icon != null) ...[
              IconTheme.merge(
                data: IconThemeData(size: 16, color: fg),
                child: icon!,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: fg),
          ],
        ),
      ),
    );
  }
}
