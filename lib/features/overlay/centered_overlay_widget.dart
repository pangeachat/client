import 'package:flutter/material.dart';

import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/widget_boundaries_model.dart';

class CenteredOverlayWidget extends StatelessWidget {
  final Widget child;
  final BuildContext outerContext;
  final bool useParentBoundaries;

  const CenteredOverlayWidget({
    super.key,
    required this.child,
    required this.outerContext,
    required this.useParentBoundaries,
  });

  @override
  Widget build(BuildContext context) {
    WidgetBoundaries boundingBox = WidgetBoundaries.defaultBoundaries;
    if (useParentBoundaries) {
      boundingBox = OverlayUtil.getBoundingBox(outerContext) ?? boundingBox;
    }

    return Positioned(
      top: boundingBox.top,
      right: boundingBox.right,
      left: boundingBox.left,
      bottom: boundingBox.bottom,
      child: child,
    );
  }
}
