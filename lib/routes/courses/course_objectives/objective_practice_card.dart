import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';

/// The Practice tile that leads the current Mission's activity row (#9438):
/// same footprint as an activity card, so the row reads as one set of things
/// to do for this Mission, with practice first. Tapping it opens vocabulary
/// practice scoped to the Mission's target words — XP earned there counts
/// toward the Mission (quests.instructions.md, "What fills a Mission").
class ObjectivePracticeCard extends StatelessWidget {
  final double width;
  final double height;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const ObjectivePracticeCard({
    required this.width,
    required this.height,
    required this.onTap,
    this.focusNode,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Semantics(
      button: true,
      label: l10n.practiceObjective,
      child: FocusRingTapTarget(
        onTap: onTap,
        focusNode: focusNode,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12.0)),
        ),
        child: ExcludeSemantics(
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Symbols.fitness_center,
                  size: 48.0,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(height: 8.0),
                Text(
                  l10n.practice,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
