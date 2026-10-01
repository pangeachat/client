import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// One chip in a [UserFilterChipRow].
class UserFilterChip {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onSelected;

  const UserFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });
}

/// The scrolling row of filter chips above a user-search list, shared by the
/// invite page and the New Direct Message panel (#9009).
///
/// Each page owns its own set of filters — the invite page's are room-scoped
/// (participants, knocking, banned) and the DM panel's are not — so only the
/// row itself, and the one group name a screen reader announces for it, are
/// shared.
class UserFilterChipRow extends StatelessWidget {
  final List<UserFilterChip> chips;

  const UserFilterChipRow({super.key, required this.chips});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: L10n.of(context).userSearchTagsLabel,
      container: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 12.0,
            children: chips.map((chip) {
              final icon = chip.icon;
              return FilterChip(
                label: icon == null
                    ? Text(chip.label)
                    : Row(
                        spacing: 4.0,
                        mainAxisSize: MainAxisSize.min,
                        children: [Icon(icon, size: 16.0), Text(chip.label)],
                      ),
                onSelected: (_) => chip.onSelected(),
                selected: chip.selected,
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
