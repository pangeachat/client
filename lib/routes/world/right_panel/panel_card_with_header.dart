import 'package:flutter/material.dart';

import 'package:fluffychat/routes/world/panel_card.dart';
import 'package:fluffychat/routes/world/panel_header.dart';

class PanelCardWithHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onLeading;
  final Widget child;
  final String tooltip;
  final Widget? trailing;

  const PanelCardWithHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.onLeading,
    this.trailing,
    required this.child,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    // No Semantics group of its own: the panel dispatchers author the one
    // named group every workspace panel gets (#8729) — a second one here
    // nested a group inside a group on every headered panel.
    return PanelCard(
      child: Column(
        children: [
          PanelHeader(
            leading: IconButton(
              tooltip: tooltip,
              icon: Icon(icon),
              onPressed: onLeading,
            ),
            title: title,
            trailing: trailing,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
