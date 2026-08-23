import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

/// The "recruiting host" badge (world-map.instructions.md, "Pin state"): a bell
/// glyph in a green circle, shown TOP-RIGHT on a pin or large card whose session
/// is still looking for players. It's the pre-ongoing counterpart of the unread
/// bubble and shares its slot: a pin shows the bell only before the room is
/// ongoing and the unread bubble only once it's ongoingActive, so the two are
/// mutually exclusive by state and never both appear.
///
/// The same white bell on the same joinable green as the course plan's ping
/// badge (`CoursePingBadge`), so one ping reads as one thing wherever the
/// learner meets it (#8484). The white ring survives from the old gold badge and
/// matters more now, not less: the joinable pin body underneath carries this
/// exact green, and the ring is what keeps the badge from dissolving into it.
class WorldMapPingedBadge extends StatelessWidget {
  const WorldMapPingedBadge({super.key});

  /// The `joinable` state green — the fill the course-plan ping badge and the
  /// open-session pin both use, which is what makes the three read as one signal.
  static const Color _fill = AppConfig.green;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: _fill,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
    ),
    child: const Icon(
      Icons.notifications_outlined,
      size: 12,
      color: Colors.white,
    ),
  );
}
