import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';

class TutorialStep {
  final TutorialEnum type;
  final int index;
  final TutorialStepData data;
  final TutorialStepStyle style;

  const TutorialStep({
    required this.type,
    required this.index,
    required this.data,
    required this.style,
  });
}

class TutorialStepData {
  final String targetKey;
  final Future<void> Function()? onTap;

  TutorialStepData({required this.targetKey, this.onTap});
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
