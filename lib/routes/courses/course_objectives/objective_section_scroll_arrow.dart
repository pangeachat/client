import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => Logs().w('pointer down ${direction.name}'),
        child: GestureDetector(
          onTap: () {
            Logs().w('tap ${direction.name}');
            onTap();
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: EdgeInsets.all(8.0),
            decoration: BoxDecoration(color: theme.colorScheme.surface),
            child: Center(child: Icon(direction.icon)),
          ),
        ),
      ),
    );
  }
}
