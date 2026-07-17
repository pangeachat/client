import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

/// The "recruiting host" badge (world-map.instructions.md, "Pin state"): a
/// raised-hand glyph in a gold circle, shown TOP-RIGHT on a pin or large card
/// whose session is still looking for players. It's the pre-ongoing counterpart
/// of the unread bubble and shares its slot: a pin shows the hand only before
/// the room is ongoing and the unread bubble only once it's ongoingActive, so
/// the two are mutually exclusive by state and never both appear.
///
/// A white hand on a **deepened** gold (the bright [AppConfig.gold] washed a
/// white glyph out) plus a white ring — matching the unread bubble's standout —
/// keeps it legible over the map. The circle is a fixed brand gold, so the white
/// hand reads in both themes.
class WorldMapPingedBadge extends StatelessWidget {
  const WorldMapPingedBadge({super.key});

  /// A darker gold than [AppConfig.gold] — same hue, deepened so the white hand
  /// reads clearly against it.
  static final Color _fill = AppConfig.yellowDark;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: _fill,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
    ),
    child: const Icon(Icons.waving_hand, size: 12),
  );
}
