import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The small gold "+N" an earned goal carries: what it paid into the
/// session's XP (#9559). Quiet on purpose — the diamond says the goal is
/// earned; this only says what it was worth. In the theme's text gold.
class GoalXpLabel extends StatelessWidget {
  final int xp;

  const GoalXpLabel({required this.xp, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Semantics(
      label: l10n.xpAmount(xp),
      child: ExcludeSemantics(
        child: Text(
          l10n.goalXpGain(xp),
          style: TextStyle(
            color: theme.pangea.gold,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
