import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// "Mission N" on a pin shown from outside the course map's selected Mission
/// (#9420 prototype) — a coursemate's live session or the learner's own
/// unfinished one. Part of the pin itself, in the pin's own state colour: atop
/// a mid teardrop (which grows by [height] to hold it, so placement makes room
/// for both) and inside a large card's title row. Small dots carry none.
class MissionPinTag extends StatelessWidget {
  final int number;
  final ActivityPinState state;

  const MissionPinTag({required this.number, required this.state, super.key});

  static const double height = 18.0;
  static const double width = 72.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 7.0),
      decoration: BoxDecoration(
        color: state.bodyColor(context),
        borderRadius: BorderRadius.circular(999.0),
      ),
      alignment: Alignment.center,
      child: Text(
        L10n.of(context).missionNumber(number),
        maxLines: 1,
        style: theme.textTheme.labelSmall?.copyWith(
          color: state.onBodyColor(context),
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}
