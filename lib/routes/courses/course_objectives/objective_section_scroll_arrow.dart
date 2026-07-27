import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

enum ArrowDirection {
  back,
  forward;

  IconData get icon => switch (this) {
    ArrowDirection.back => Icons.chevron_left,
    ArrowDirection.forward => Icons.chevron_right,
  };

  String label(L10n l10n) => switch (this) {
    ArrowDirection.back => l10n.back,
    ArrowDirection.forward => l10n.forward,
  };
}

class ObjectiveSectionScrollArrow extends StatelessWidget {
  final ArrowDirection direction;
  final VoidCallback onTap;
  const ObjectiveSectionScrollArrow({
    super.key,
    required this.direction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return BlockSemantics(
      child: Semantics(
        button: true,
        label: direction.label(l10n),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 40.0,
              padding: EdgeInsets.all(8.0),
              decoration: BoxDecoration(color: theme.colorScheme.surface),
              child: Center(child: Icon(direction.icon)),
            ),
          ),
        ),
      ),
    );
  }
}
