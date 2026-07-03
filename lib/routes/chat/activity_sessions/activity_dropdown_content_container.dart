import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';

class ActivityDropdownContentContainer extends StatelessWidget {
  final bool showDropdown;
  final Function(bool) setShowDropdown;
  final Widget child;

  const ActivityDropdownContentContainer({
    super.key,
    required this.showDropdown,
    required this.setShowDropdown,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      clipBehavior: Clip.antiAlias,
      child: AnimatedAlign(
        duration: FluffyThemes.animationDuration,
        curve: Curves.easeInOut,
        heightFactor: showDropdown ? 1.0 : 0.0,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onPanUpdate: (details) {
            if (details.delta.dy < -2) {
              setShowDropdown(false);
            }
          },
          child: child,
        ),
      ),
    );
  }
}
