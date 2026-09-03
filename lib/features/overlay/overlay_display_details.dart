import 'package:flutter/material.dart';

sealed class OverlayDisplayDetails {
  final String overlayKey;

  final Color? borderColor;
  final Color? backgroundColor;

  final bool rootOverlay;
  final bool bypassBlockingOverlays;
  final bool blurBackground;

  final bool backDropToDismiss;
  final bool closePrevOverlay;
  final bool ignorePointer;

  /// Makes the overlay's own content opaque to hit testing — both Flutter's
  /// hit test and, on web, the semantics DOM — so taps that land on it never
  /// fall through to whatever sits behind the overlay (#8181).
  /// Off by default: decorative overlays (animations, confetti) cover large
  /// areas and must stay click-through.
  final bool blockPointerThrough;

  /// Names the overlay as a modal layer to assistive tech (#8783). Everything
  /// painted behind it in the same panel drops out of the semantics tree, the
  /// backdrop becomes a "Dismiss" control, and the content is a named route
  /// scope — the shape a `ModalRoute` publishes — so a screen reader moves
  /// into the overlay when it opens and sees nothing else until it closes.
  /// Null (the default) for overlays that float over content the user is
  /// still browsing: word cards, popups, animations.
  final String? modalSemanticsLabel;

  final bool canPop;

  final VoidCallback? onDismiss;

  const OverlayDisplayDetails({
    required this.overlayKey,
    this.borderColor,
    this.backgroundColor,
    this.rootOverlay = false,
    this.bypassBlockingOverlays = false,
    this.blurBackground = false,
    this.backDropToDismiss = true,
    this.closePrevOverlay = true,
    this.ignorePointer = false,
    this.blockPointerThrough = false,
    this.modalSemanticsLabel,
    this.canPop = true,
    this.onDismiss,
  });
}

class TransformOverlayDisplayDetails extends OverlayDisplayDetails {
  final String transformTargetId;

  final Alignment targetAnchor;
  final Alignment followerAnchor;

  final Offset? offset;

  const TransformOverlayDisplayDetails({
    required this.transformTargetId,
    this.targetAnchor = Alignment.topCenter,
    this.followerAnchor = Alignment.bottomCenter,
    this.offset,

    required super.overlayKey,
    super.borderColor,
    super.backgroundColor,
    super.rootOverlay = false,
    super.bypassBlockingOverlays = false,
    super.blurBackground = false,
    super.backDropToDismiss = true,
    super.closePrevOverlay = true,
    super.ignorePointer = false,
    super.blockPointerThrough = false,
    super.modalSemanticsLabel,
    super.canPop = true,
    super.onDismiss,
  });

  TransformOverlayDisplayDetails copyWith({
    String? transformTargetId,
    Alignment? targetAnchor,
    Alignment? followerAnchor,
    Offset? offset,
  }) => TransformOverlayDisplayDetails(
    transformTargetId: transformTargetId ?? this.transformTargetId,
    targetAnchor: targetAnchor ?? this.targetAnchor,
    followerAnchor: followerAnchor ?? this.followerAnchor,
    offset: offset ?? this.offset,
    overlayKey: overlayKey,
    borderColor: borderColor,
    backgroundColor: backgroundColor,
    rootOverlay: rootOverlay,
    bypassBlockingOverlays: bypassBlockingOverlays,
    blurBackground: blurBackground,
    backDropToDismiss: backDropToDismiss,
    closePrevOverlay: closePrevOverlay,
    ignorePointer: ignorePointer,
    blockPointerThrough: blockPointerThrough,
    modalSemanticsLabel: modalSemanticsLabel,
    canPop: canPop,
    onDismiss: onDismiss,
  );
}

class CenteredOverlayDisplayDetails extends OverlayDisplayDetails {
  const CenteredOverlayDisplayDetails({
    required super.overlayKey,
    super.borderColor,
    super.backgroundColor,
    super.rootOverlay = false,
    super.bypassBlockingOverlays = false,
    super.blurBackground = false,
    super.backDropToDismiss = true,
    super.closePrevOverlay = true,
    super.ignorePointer = false,
    super.blockPointerThrough = false,
    super.modalSemanticsLabel,
    super.canPop = true,
    super.onDismiss,
  });
}

class TopOverlayDisplayDetails extends OverlayDisplayDetails {
  const TopOverlayDisplayDetails({
    required super.overlayKey,
    super.borderColor,
    super.backgroundColor,
    super.rootOverlay = false,
    super.bypassBlockingOverlays = false,
    super.blurBackground = false,
    super.backDropToDismiss = true,
    super.closePrevOverlay = true,
    super.ignorePointer = false,
    super.blockPointerThrough = false,
    super.modalSemanticsLabel,
    super.canPop = true,
    super.onDismiss,
  });
}

class PositionedOverlayDisplayDetails extends TransformOverlayDisplayDetails {
  final double maxWidth;
  final double maxHeight;

  final bool addBorder;
  final bool isScrollable;

  const PositionedOverlayDisplayDetails({
    required this.maxWidth,
    required this.maxHeight,
    this.addBorder = true,
    this.isScrollable = true,

    required super.transformTargetId,
    super.targetAnchor,
    super.followerAnchor,
    super.offset,

    required super.overlayKey,
    super.borderColor,
    super.backgroundColor,
    super.rootOverlay = false,
    super.bypassBlockingOverlays = false,
    super.blurBackground = false,
    super.backDropToDismiss = true,
    super.closePrevOverlay = true,
    super.ignorePointer = false,
    super.blockPointerThrough = false,
    super.modalSemanticsLabel,
    super.canPop = true,
    super.onDismiss,
  });
}
