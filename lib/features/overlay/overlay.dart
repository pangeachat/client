import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/features/overlay/centered_overlay_widget.dart';
import 'package:fluffychat/features/overlay/overlay_container.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/features/overlay/top_overlay_widget.dart';
import 'package:fluffychat/features/overlay/transparent_backdrop.dart';
import '../../pangea/common/utils/error_handler.dart';
import '../../widgets/matrix.dart';

class OverlayUtil {
  static bool showOverlay({
    required BuildContext context,
    required Widget child,
    required OverlayDisplayDetails displayDetails,
  }) {
    try {
      if (displayDetails.closePrevOverlay) {
        MatrixState.pAnyState.closeOverlay();
      }

      final OverlayEntry entry = OverlayEntry(
        builder: (_) => Stack(
          children: [
            if (displayDetails.backDropToDismiss)
              IgnorePointer(
                ignoring: displayDetails.ignorePointer,
                child: TransparentBackdrop(
                  backgroundColor: displayDetails.backgroundColor,
                  onDismiss: displayDetails.onDismiss,
                  blurBackground: displayDetails.blurBackground,
                ),
              ),
            switch (displayDetails) {
              TransformOverlayDisplayDetails(
                transformTargetId: final targetId,
                targetAnchor: final targetAnchor,
                followerAnchor: final followerAnchor,
                offset: final offset,
              ) =>
                CompositedTransformFollower(
                  targetAnchor: targetAnchor,
                  followerAnchor: followerAnchor,
                  link: MatrixState.pAnyState.layerLinkAndKey(targetId).link,
                  showWhenUnlinked: false,
                  offset: offset ?? Offset.zero,
                  child: child,
                ),
              CenteredOverlayDisplayDetails() => CenteredOverlayWidget(
                child: child,
              ),
              TopOverlayDisplayDetails() => TopOverlayWidget(child: child),
            },
          ],
        ),
      );

      return MatrixState.pAnyState.openOverlay(
        entry,
        context,
        overlayKey: displayDetails.overlayKey,
        canPop: displayDetails.canPop,
        rootOverlay: displayDetails.rootOverlay,
        bypassBlockingOverlays: displayDetails.bypassBlockingOverlays,
      );
    } catch (err, stack) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(e: err, s: stack, data: {});
      return false;
    }
  }

  static void showPositionedCard({
    required BuildContext context,
    required Widget cardToShow,
    required PositionedOverlayDisplayDetails displayDetails,
  }) {
    try {
      final targetRenderBox = MatrixState.pAnyState.getRenderBox(
        displayDetails.transformTargetId,
      );

      final parentRenderBox =
          Overlay.of(context).context.findRenderObject() as RenderBox?;
      if (parentRenderBox == null || !parentRenderBox.hasSize) {
        debugPrint("Cannot get renderbox for parent overlay");
        return;
      }

      if (targetRenderBox == null) {
        debugPrint("layerLinkAndKey.key.currentContext is null");
        return;
      }

      final offset = _getPositionedOffset(
        context,
        targetRenderBox,
        parentRenderBox,
        displayDetails.maxWidth,
      );

      final hasTopOverflow = _hasTopOverflow(
        targetRenderBox,
        displayDetails.maxHeight,
      );

      final Widget child = displayDetails.addBorder
          ? Material(
              borderOnForeground: false,
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              child: OverlayContainer(
                cardToShow: cardToShow,
                maxHeight: displayDetails.maxHeight,
                maxWidth: displayDetails.maxWidth,
                isScrollable: displayDetails.isScrollable,
              ),
            )
          : cardToShow;

      showOverlay(
        context: context,
        child: child,
        displayDetails: displayDetails.copyWith(
          offset: offset,
          targetAnchor: hasTopOverflow
              ? Alignment.bottomCenter
              : Alignment.topCenter,
          followerAnchor: hasTopOverflow
              ? Alignment.topCenter
              : Alignment.bottomCenter,
        ),
      );
    } catch (err, stack) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(e: err, s: stack, data: {});
    }
  }

  static Offset _getPositionedOffset(
    BuildContext context,
    RenderBox targetRenderBox,
    RenderBox parentRenderBox,
    double maxWidth,
  ) {
    const horizontalPadding = 10.0;

    final targetSize = targetRenderBox.size;
    final targetOffset = parentRenderBox.globalToLocal(
      targetRenderBox.localToGlobal(Offset.zero),
    );

    final midpoint = targetOffset.dx + (targetSize.width / 2);
    final leftEdge = midpoint - (maxWidth / 2);
    final rightEdge = midpoint + (maxWidth / 2);

    final minLeft = horizontalPadding;
    final maxRight = parentRenderBox.size.width - horizontalPadding;

    double dx = 0;

    if (leftEdge < minLeft) {
      dx = minLeft - leftEdge;
    } else if (rightEdge > maxRight) {
      dx = maxRight - rightEdge;
    }

    return Offset(dx, 0);
  }

  static bool _hasTopOverflow(RenderBox renderBox, double maxHeight) {
    final targetOffset = (renderBox).localToGlobal(Offset.zero);
    return maxHeight + kToolbarHeight > targetOffset.dy;
  }
}
