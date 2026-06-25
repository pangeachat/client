import 'package:flutter/material.dart';

import 'package:fluffychat/routes/world/panel_card.dart';
import 'package:fluffychat/routes/world/panel_header.dart';

class PanelCardWithHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onLeading;
  final Widget child;
  final String tooltip;

  const PanelCardWithHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.onLeading,
    required this.child,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
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
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
