import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/features/overlay/centered_overlay_widget.dart';
import 'package:fluffychat/features/overlay/overlay_container.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/features/overlay/top_overlay_widget.dart';
import 'package:fluffychat/features/overlay/transparent_backdrop.dart';
import 'package:fluffychat/features/overlay/widget_boundaries_model.dart';
import '../../config/themes.dart';
import '../../pangea/common/utils/error_handler.dart';
import '../../widgets/matrix.dart';

class OverlayUtil {
  static WidgetBoundaries? getBoundingBox(BuildContext context) {
    try {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return null;

      final size = renderBox.size;
      final offset = renderBox.localToGlobal(Offset.zero);
      final screenSize = MediaQuery.sizeOf(context);
      final top = offset.dy;
      final left = offset.dx;
      final bottom = screenSize.height - (top + size.height);
      final right = screenSize.width - (left + size.width);

      return WidgetBoundaries(
        left: left,
        right: right,
        top: top,
        bottom: bottom,
      );
    } catch (_) {
      return null;
    }
  }

  /// The dismiss backdrop. Confined to the opening context's rect when
  /// [OverlayDisplayDetails.boundBackdropToParent] is set (so a chat toolbar
  /// overlay dims only its panel, not the whole screen — #7157); otherwise it
  /// fills the screen as before.
  static Widget _backdrop(
    BuildContext context,
    OverlayDisplayDetails displayDetails,
  ) {
    final WidgetBoundaries bounds = displayDetails.boundBackdropToParent
        ? (getBoundingBox(context) ?? WidgetBoundaries.defaultBoundaries)
        : WidgetBoundaries.defaultBoundaries;
    return Positioned(
      top: bounds.top,
      bottom: bounds.bottom,
      left: bounds.left,
      right: bounds.right,
      child: IgnorePointer(
        ignoring: displayDetails.ignorePointer,
        child: TransparentBackdrop(
          backgroundColor: displayDetails.backgroundColor,
          onDismiss: displayDetails.onDismiss,
          blurBackground: displayDetails.blurBackground,
        ),
      ),
    );
  }

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
              _backdrop(context, displayDetails),
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
              CenteredOverlayDisplayDetails(
                useParentBoundaries: final useParentBoundaries,
              ) =>
                CenteredOverlayWidget(
                  outerContext: context,
                  useParentBoundaries: useParentBoundaries,
                  child: child,
                ),
              TopOverlayDisplayDetails(
                useParentBoundaries: final useParentBoundaries,
              ) =>
                TopOverlayWidget(
                  outerContext: context,
                  useParentBoundaries: useParentBoundaries,
                  child: child,
                ),
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
      final renderBox = MatrixState.pAnyState.getRenderBox(
        displayDetails.transformTargetId,
      );

      if (renderBox == null) {
        debugPrint("layerLinkAndKey.key.currentContext is null");
        return;
      }

      final offset = _getPositionedOffset(
        context,
        renderBox,
        displayDetails.maxWidth,
      );

      final hasTopOverflow = _hasTopOverflow(
        renderBox,
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
    RenderBox renderBox,
    double maxWidth,
  ) {
    final targetOffset = (renderBox).localToGlobal(Offset.zero);
    final targetSize = renderBox.size;

    final screenWidth = MediaQuery.widthOf(context);
    final columnWidth = FluffyThemes.isColumnMode(context)
        ? FluffyThemes.columnWidth + FluffyThemes.navRailWidth
        : 0;

    final horizontalMidpoint =
        (targetOffset.dx - columnWidth) + (targetSize.width / 2);
    final halfMaxWidth = maxWidth / 2;

    final hasLeftOverflow = (horizontalMidpoint - halfMaxWidth) < 10;
    final hasRightOverflow =
        (horizontalMidpoint + halfMaxWidth) > (screenWidth - columnWidth - 10);

    if (hasLeftOverflow) {
      final xOffset = (horizontalMidpoint - halfMaxWidth - 10) * -1;
      return Offset(xOffset, 0);
    }

    if (hasRightOverflow) {
      final xOffset =
          (screenWidth - columnWidth) -
          (horizontalMidpoint + halfMaxWidth + 10);
      return Offset(xOffset, 0);
    }

    return Offset(0, 0);
  }

  static bool _hasTopOverflow(RenderBox renderBox, double maxHeight) {
    final targetOffset = (renderBox).localToGlobal(Offset.zero);
    return maxHeight + kToolbarHeight > targetOffset.dy;
  }
}
