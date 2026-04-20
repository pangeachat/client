import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';

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

class TutorialStep {
  final TutorialStepData data;
  final TutorialStepStyle style;

  const TutorialStep({required this.data, required this.style});
}

sealed class TutorialModel {
  final TutorialEnum tutorialType;
  final List<TutorialStepData> stepsData;

  const TutorialModel({required this.tutorialType, required this.stepsData});

  List<TutorialStepStyle> stepStyles(L10n l10n);

  List<TutorialStep> steps(L10n l10n) {
    final styles = stepStyles(l10n);
    return List.generate(
      stepsData.length,
      (index) => TutorialStep(data: stepsData[index], style: styles[index]),
    );
  }

  static TutorialSequenceModel get chatTutorialSequence =>
      TutorialSequenceModel(
        tutorials: [
          TutorialEnum.readingAssistance,
          TutorialEnum.selectModeButtons,
          TutorialEnum.writingAssistance,
        ],
      );
}

class ReadingAssistantTutorialModel extends TutorialModel {
  ReadingAssistantTutorialModel({required List<TutorialStepData> data})
    : assert(data.length == TutorialEnum.readingAssistance.stepCount),
      super(tutorialType: TutorialEnum.readingAssistance, stepsData: data);

  @override
  List<TutorialStepStyle> stepStyles(L10n l10n) => [
    TutorialStepStyle(
      tooltip: l10n.readingAssistanceTutorialClickMessage,
      tooltipSize: Size(250, 100),
      borderRadius: AppConfig.borderRadius,
    ),
  ];
}

class WritingAssistantTutorialModel extends TutorialModel {
  WritingAssistantTutorialModel({required List<TutorialStepData> data})
    : assert(data.length == TutorialEnum.writingAssistance.stepCount),
      super(tutorialType: TutorialEnum.writingAssistance, stepsData: data);

  @override
  List<TutorialStepStyle> stepStyles(L10n l10n) => [
    TutorialStepStyle(
      tooltip: l10n.writingAssistanceTutorialInputBar,
      tooltipSize: Size(300, 120),
      borderRadius: 24.0,
    ),
    TutorialStepStyle(
      tooltip: l10n.writingAssistanceTutorialIGCButton,
      tooltipSize: Size(300, 120),
      borderRadius: 100.0,
      padding: 4.0,
    ),
  ];
}

class SelectModeButtonsTutorialModel extends TutorialModel {
  SelectModeButtonsTutorialModel({required List<TutorialStepData> data})
    : assert(data.length == TutorialEnum.selectModeButtons.stepCount),
      super(tutorialType: TutorialEnum.selectModeButtons, stepsData: data);

  @override
  List<TutorialStepStyle> stepStyles(L10n l10n) => [
    TutorialStepStyle(
      tooltip: l10n.selectModeTutorialTranslate,
      tooltipSize: Size(250, 100),
      borderRadius: 100.0,
      padding: 0.0,
    ),
    TutorialStepStyle(
      tooltip: l10n.selectModeTutorialAudio,
      tooltipSize: Size(250, 100),
      borderRadius: 100.0,
      padding: 0.0,
    ),
    TutorialStepStyle(
      tooltip: l10n.selectModeTutorialExit,
      tooltipSize: Size(250, 100),
      borderRadius: AppConfig.borderRadius,
    ),
  ];
}

class TutorialSequenceModel {
  final List<TutorialEnum> tutorials;

  const TutorialSequenceModel({required this.tutorials});
}
