import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_step_model.dart';

typedef TutorialSequence = List<TutorialEnum>;

sealed class TutorialModel {
  final TutorialEnum tutorialType;
  final List<TutorialStepData> _stepsData;

  const TutorialModel({
    required this.tutorialType,
    required List<TutorialStepData> stepsData,
  }) : _stepsData = stepsData;

  List<TutorialStepStyle> _stepStyles(L10n l10n);

  TutorialStep step(int index, L10n l10n) {
    final styles = _stepStyles(l10n);
    return TutorialStep(data: _stepsData[index], style: styles[index]);
  }
}

class ReadingAssistantTutorialModel extends TutorialModel {
  ReadingAssistantTutorialModel({required List<TutorialStepData> data})
    : assert(data.length == TutorialEnum.readingAssistance.stepCount),
      super(tutorialType: TutorialEnum.readingAssistance, stepsData: data);

  @override
  List<TutorialStepStyle> _stepStyles(L10n l10n) => [
    TutorialStepStyle(
      tooltip: l10n.readingAssistanceTutorialClickMessage,
      tooltipSize: Size(250, 120),
      borderRadius: AppConfig.borderRadius,
    ),
  ];
}

class WritingAssistantTutorialModel extends TutorialModel {
  WritingAssistantTutorialModel({required List<TutorialStepData> data})
    : assert(data.length == TutorialEnum.writingAssistance.stepCount),
      super(tutorialType: TutorialEnum.writingAssistance, stepsData: data);

  @override
  List<TutorialStepStyle> _stepStyles(L10n l10n) => [
    TutorialStepStyle(
      tooltip: l10n.writingAssistanceTutorialInputBar,
      tooltipSize: Size(300, 140),
      borderRadius: 24.0,
    ),
    TutorialStepStyle(
      tooltip: l10n.writingAssistanceTutorialIGCButton,
      tooltipSize: Size(300, 140),
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
  List<TutorialStepStyle> _stepStyles(L10n l10n) => [
    TutorialStepStyle(
      tooltip: l10n.selectModeTutorialTranslate,
      tooltipSize: Size(250, 120),
      borderRadius: 100.0,
      padding: 0.0,
    ),
    TutorialStepStyle(
      tooltip: l10n.selectModeTutorialAudio,
      tooltipSize: Size(250, 120),
      borderRadius: 100.0,
      padding: 0.0,
    ),
    TutorialStepStyle(
      tooltip: l10n.selectModeTutorialExit,
      tooltipSize: Size(250, 120),
      borderRadius: AppConfig.borderRadius,
    ),
  ];
}
