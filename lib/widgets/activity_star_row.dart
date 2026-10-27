import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/goal_diamond.dart';

/// An activity's goal row: one [GoalDiamond] per goal, filled as the learner
/// earns it. Diamonds, not stars — a star marks a Mission, and an activity's
/// goals are the diamonds that pay XP into it (quests.instructions.md, "Stars
/// and goal diamonds").
class ActivityStarRow extends StatelessWidget {
  final int total;
  final int earned;
  final double iconSize;
  final bool condensed;

  const ActivityStarRow({
    super.key,
    required this.total,
    required this.earned,
    this.iconSize = 16,
    this.condensed = false,
  });

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    final filled = earned.clamp(0, total);
    if (condensed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2.0,
        children: [
          Text(
            "$filled/$total",
            style: TextStyle(
              fontSize: iconSize,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          GoalDiamond(earned: true, size: iconSize),
        ],
      );
    }
    return Semantics(
      label: L10n.of(context).goalsCompletedOfTotal(filled, total),
      // Scale down rather than wrap. Every host gives this row a box that can't
      // grow — the role card's fixed 125, the suggestion card, the map card's
      // SizedBox(height: 16) — so a second run paints outside the card (#8595).
      // Shrinking keeps it one row; [condensed] is the fallback for counts too
      // high to stay readable at any scale.
      //
      // Start-aligned, not the FittedBox default of centred: a host that hands
      // this a tight width would otherwise float the stars in whatever space
      // is left over, so the same row sat at a different offset depending on
      // its neighbours -- the Stars list's rows drifted with the presence of a
      // CEFR label (#9032). Hosts that want it centred centre it themselves.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2.0,
          children: List.generate(
            total,
            (i) => GoalDiamond(earned: i < filled, size: iconSize),
          ),
        ),
      ),
    );
  }
}
