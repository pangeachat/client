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
  final bool canPop;

  /// Confine the dismiss backdrop (and so the dimming) to the rect of the
  /// context that opened the overlay, instead of the whole screen. Lets a chat
  /// toolbar overlay dim only its panel in world_v2 (#7157). Default false keeps
  /// the historical full-screen backdrop.
  final bool boundBackdropToParent;

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
    this.canPop = true,
    this.boundBackdropToParent = false,
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
    canPop: canPop,
    onDismiss: onDismiss,
  );
}

class CenteredOverlayDisplayDetails extends OverlayDisplayDetails {
  final bool useParentBoundaries;

  const CenteredOverlayDisplayDetails({
    this.useParentBoundaries = true,

    required super.overlayKey,
    super.borderColor,
    super.backgroundColor,
    super.rootOverlay = false,
    super.bypassBlockingOverlays = false,
    super.blurBackground = false,
    super.backDropToDismiss = true,
    super.closePrevOverlay = true,
    super.ignorePointer = false,
    super.canPop = true,
    super.boundBackdropToParent = false,
    super.onDismiss,
  });
}

class TopOverlayDisplayDetails extends OverlayDisplayDetails {
  final bool useParentBoundaries;

  const TopOverlayDisplayDetails({
    this.useParentBoundaries = true,

    required super.overlayKey,
    super.borderColor,
    super.backgroundColor,
    super.rootOverlay = false,
    super.bypassBlockingOverlays = false,
    super.blurBackground = false,
    super.backDropToDismiss = true,
    super.closePrevOverlay = true,
    super.ignorePointer = false,
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
    super.canPop = true,
    super.onDismiss,
  });
}
