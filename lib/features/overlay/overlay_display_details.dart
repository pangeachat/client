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
  final bool blockSemantics;

  /// Makes the overlay's own content opaque to hit testing — both Flutter's
  /// hit test and, on web, the semantics DOM — so taps that land on it never
  /// fall through to whatever sits behind the overlay (#8181).
  /// Off by default: decorative overlays (animations, confetti) cover large
  /// areas and must stay click-through.
  final bool blockPointerThrough;

  /// Makes the overlay modal to the keyboard, the way [blockSemantics] makes
  /// it modal to a screen reader: Tab cycles through the overlay's own
  /// controls, Escape dismisses it, and closing hands focus back to whatever
  /// held it when the overlay opened (#9191). Off by default: most overlays
  /// are cards or decorations beside page content the learner still uses.
  final bool keyboardModal;

  /// Controls that stay reachable while this overlay is up, rendered above
  /// the backdrop at their own place on the page: followers onto page widgets,
  /// sized to them. A tap there reaches them instead of dismissing; a tap
  /// anywhere else still lands on the backdrop. Null for the default, where
  /// nothing but the overlay's own content sits above the backdrop.
  ///
  /// Why not a hole in the backdrop: with the semantics tree on, the web
  /// engine turns a click on the backdrop's Dismiss node into a semantics tap
  /// on that node and drops the pointer events, so a Flutter-side hit-test
  /// hole never sees the click (#9122). Only a node painted above Dismiss
  /// wins, and that means a node inside this overlay.
  final Widget? aboveBackdrop;

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
    this.blockSemantics = false,
    this.blockPointerThrough = false,
    this.keyboardModal = false,
    this.canPop = true,
    this.onDismiss,
    this.aboveBackdrop,
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
    super.blockSemantics = false,
    super.blockPointerThrough = false,
    super.canPop = true,
    super.onDismiss,
    super.aboveBackdrop,
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
    canPop: canPop,
    onDismiss: onDismiss,
    aboveBackdrop: aboveBackdrop,
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
    super.blockSemantics = false,
    super.blockPointerThrough = false,
    super.keyboardModal = false,
    super.canPop = true,
    super.onDismiss,
    super.aboveBackdrop,
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
    super.canPop = true,
    super.onDismiss,
    super.aboveBackdrop,
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
    super.canPop = true,
    super.onDismiss,
    super.aboveBackdrop,
  });
}
