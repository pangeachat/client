import 'package:flutter/material.dart';

class TutorialStep {
  final TutorialStepData data;
  final TutorialStepStyle style;

  const TutorialStep({required this.data, required this.style});
}

class TutorialStepData {
  final GlobalKey targetKey;
  final LayerLink targetLink;
  final Future<void> Function()? onTap;

  TutorialStepData({
    required this.targetKey,
    required this.targetLink,
    this.onTap,
  });
}

class TutorialStepStyle {
  final String tooltip;
  final Size tooltipSize;
  final double? borderRadius;
  final double? padding;

  const TutorialStepStyle({
    required this.tooltip,
    required this.tooltipSize,
    this.borderRadius,
    this.padding,
  });
}
