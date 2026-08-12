import 'dart:ui' as ui show SemanticsHitTestBehavior;

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
    // The opaque hit test is what keeps a tap on the arrow from falling through
    // to the card node it overlaps (#7803): the engine gives this node pointer
    // events and z-orders it above earlier-painted siblings — same tool
    // ModalRoute uses, and the same fix as the WA span card (#8181). It guards
    // only the arrow's own strip, so the cards keep their nodes (#8011). Do NOT
    // wrap this in an AbsorbPointer / IgnorePointer (strips this node's
    // semantics) and do NOT re-add a BlockSemantics beside the arrows (drops
    // every card node in the row).
    return Semantics(
      container: true,
      hitTestBehavior: ui.SemanticsHitTestBehavior.opaque,
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
