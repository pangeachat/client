import 'package:flutter/material.dart';

import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_constants.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The one popup slot above the message input field, shared by the span card
/// and the suggestion card: as wide as the input field, and as tall as the
/// space above it, so choices are visible without scrolling (#8130). Both
/// cards size to their content inside it and wear the same chrome, so the
/// learner sees one component that changes what it holds.
class WritingAssistancePopupSlot {
  /// Used when the input field or the overlay cannot be measured — a composer
  /// torn down for a recording, or one not yet laid out.
  static const double _unmeasured = 325.0;

  /// Below this the slot stops shrinking and the card scrolls its content
  /// instead of collapsing to a few unusable lines.
  static const double _minHeight = 200.0;

  /// Clearance left between the top of the slot and the chat's app bar.
  static const double _topClearance = 16.0;

  /// The padding and border `OverlayContainer` draws, top and bottom. What is
  /// left over is the card's own.
  static const double _containerChrome = 24.0;

  final double maxWidth;
  final double maxHeight;

  const WritingAssistancePopupSlot({
    required this.maxWidth,
    required this.maxHeight,
  });

  WritingAssistancePopupSlot.above({
    required double inputWidth,
    required double spaceAboveInput,
  }) : maxWidth = inputWidth,
       maxHeight = (spaceAboveInput - kToolbarHeight - _topClearance).clamp(
         _minHeight,
         double.infinity,
       );

  factory WritingAssistancePopupSlot.measure(BuildContext context) {
    final inputRenderBox = MatrixState.pAnyState.getRenderBox(
      ChoreoConstants.inputTransformTargetKey,
    );
    final overlayRenderBox = OverlayUtil.overlayRenderBox(context);

    if (inputRenderBox == null || overlayRenderBox == null) {
      return const WritingAssistancePopupSlot(
        maxWidth: _unmeasured,
        maxHeight: _unmeasured,
      );
    }

    return WritingAssistancePopupSlot.above(
      inputWidth: inputRenderBox.size.width,
      spaceAboveInput: OverlayUtil.localOffset(
        inputRenderBox,
        overlayRenderBox,
      ).dy,
    );
  }

  /// The height the card itself may fill, inside the container's chrome.
  double get cardMaxHeight => maxHeight - _containerChrome;
}
