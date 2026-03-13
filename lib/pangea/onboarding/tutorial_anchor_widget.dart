import 'package:fluffychat/pangea/onboarding/tutorial_anchor_registry.dart';
import 'package:flutter/material.dart';

class TutorialAnchor extends StatelessWidget {
  final String id;
  final Widget child;
  final bool register;

  const TutorialAnchor({
    super.key,
    required this.id,
    required this.child,
    this.register = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!register) return child;
    final key = TutorialAnchorRegistry.instance.register(id);
    return KeyedSubtree(key: key, child: child);
  }
}
