import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/features/overlay/centered_overlay_widget.dart';
import 'package:fluffychat/features/overlay/overlay_container.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/features/overlay/overlay_position.dart';
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
    OverlayPosition? overlayPosition,
  }) {
    try {
      final targetRenderBox = MatrixState.pAnyState.getRenderBox(
        displayDetails.transformTargetId,
      );

      final parentRenderBox = overlayRenderBox(context);

      if (parentRenderBox == null || targetRenderBox == null) {
        debugPrint("Cannot get renderbox for parent overlay or target");
        return;
      }

      const horizontalPadding = 10.0;

      final targetSize = targetRenderBox.size;
      final targetOffset = parentRenderBox.globalToLocal(
        targetRenderBox.localToGlobal(Offset.zero),
      );

      final midpoint = targetOffset.dx + (targetSize.width / 2);
      final leftEdge = midpoint - (displayDetails.maxWidth / 2);
      final rightEdge = midpoint + (displayDetails.maxWidth / 2);

      final minLeft = horizontalPadding;
      final maxRight = parentRenderBox.size.width - horizontalPadding;

      double dx = 0;

      if (leftEdge < minLeft) {
        dx = minLeft - leftEdge;
      } else if (rightEdge > maxRight) {
        dx = maxRight - rightEdge;
      }

      final offset = Offset(dx, 0);
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

      final hasTopOverflow =
          (displayDetails.maxHeight + kToolbarHeight) > targetOffset.dy;

      final targetAnchor =
          overlayPosition?.targetAnchor ??
          (hasTopOverflow ? Alignment.bottomCenter : Alignment.topCenter);

      final followerAnchor =
          overlayPosition?.followerAnchor ??
          (hasTopOverflow ? Alignment.topCenter : Alignment.bottomCenter);

      showOverlay(
        context: context,
        child: child,
        displayDetails: displayDetails.copyWith(
          offset: offset,
          targetAnchor: targetAnchor,
          followerAnchor: followerAnchor,
        ),
      );
    } catch (err, stack) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(e: err, s: stack, data: {});
    }
  }

  static RenderBox? overlayRenderBox(BuildContext context) {
    final renderBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;

    if (renderBox == null || !renderBox.hasSize) return null;
    return renderBox;
  }
}
