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
    // Expose the arrow as an explicit button. On Flutter web, when the
    // accessibility layer is active, pointer events are dispatched through the
    // semantics DOM tree rather than the render tree, so the arrow needs its own
    // tappable semantics node that sits on top of the activity cards beneath it.
    // The caller drops the card semantics underneath (a sibling BlockSemantics)
    // so the cards can't intercept the tap (#7803). Do NOT wrap this in an
    // AbsorbPointer / IgnorePointer: those strip this node's semantics and
    // reintroduce the click-through.
    return Semantics(
      button: true,
      label: direction.label(L10n.of(context)),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(color: theme.colorScheme.surface),
            child: Center(child: Icon(direction.icon)),
          ),
        ),
      ),
    );
  }
}
