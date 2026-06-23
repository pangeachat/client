import 'package:flutter/material.dart';

import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/widget_boundaries_model.dart';

class CenteredOverlayWidget extends StatelessWidget {
  final Widget child;
  final BuildContext outerContext;

  const CenteredOverlayWidget({
    super.key,
    required this.child,
    required this.outerContext,
  });

  @override
  Widget build(BuildContext context) {
    final boundingBox =
        OverlayUtil.getBoundingBox(outerContext) ??
        WidgetBoundaries.defaultBoundaries;

    return Positioned(
      top: boundingBox.top,
      right: boundingBox.right,
      left: boundingBox.left,
      bottom: boundingBox.bottom,
      child: child,
    );
  }
}
