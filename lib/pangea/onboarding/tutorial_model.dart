import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_tooltip_widget.dart';

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
  final Widget tooltip;
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

  List<TutorialStepStyle> get stepStyles {
    throw UnimplementedError("stepStyles must be implemented by subclasses");
  }

  List<TutorialStep> get steps => List.generate(
    stepsData.length,
    (index) => TutorialStep(data: stepsData[index], style: stepStyles[index]),
  );
}

class ReadingAssistantTutorialModel extends TutorialModel {
  ReadingAssistantTutorialModel({required List<TutorialStepData> data})
    : assert(data.length == 1),
      super(tutorialType: TutorialEnum.readingAssistance, stepsData: data);

  @override
  List<TutorialStepStyle> get stepStyles => [
    TutorialStepStyle(
      tooltip: TutorialTooltipWidget(
        text: "Click on message bubble to select them",
      ),
      tooltipSize: Size(200, 80),
      borderRadius: AppConfig.borderRadius,
    ),
  ];
}

class WritingAssistantTutorialModel extends TutorialModel {
  WritingAssistantTutorialModel({required List<TutorialStepData> data})
    : assert(data.length == 2),
      super(tutorialType: TutorialEnum.writingAssistance, stepsData: data);

  @override
  List<TutorialStepStyle> get stepStyles => [
    TutorialStepStyle(
      tooltip: TutorialTooltipWidget(
        text:
            "You can write in any language. Don't worry about mistakes! We'll help you correct them.",
      ),
      tooltipSize: Size(300, 80),
      borderRadius: 24.0,
    ),
    TutorialStepStyle(
      tooltip: TutorialTooltipWidget(
        text:
            "After writing your message, click this button to start writing assistance",
      ),
      tooltipSize: Size(300, 80),
      borderRadius: 100.0,
      padding: 4.0,
    ),
  ];
}

class SelectModeButtonsTutorialModel extends TutorialModel {
  SelectModeButtonsTutorialModel({required List<TutorialStepData> data})
    : assert(data.length == 3),
      super(tutorialType: TutorialEnum.selectModeButtons, stepsData: data);

  @override
  List<TutorialStepStyle> get stepStyles => [
    TutorialStepStyle(
      tooltip: TutorialTooltipWidget(
        text: "Click here to translate the message",
      ),
      tooltipSize: Size(200, 80),
      borderRadius: 100.0,
      padding: 0.0,
    ),
    TutorialStepStyle(
      tooltip: TutorialTooltipWidget(
        text: "Click here to listen to the message",
      ),
      tooltipSize: Size(200, 80),
      borderRadius: 100.0,
      padding: 0.0,
    ),
    TutorialStepStyle(
      tooltip: TutorialTooltipWidget(
        text: "Click the background to go back to chatting",
      ),
      tooltipSize: Size(200, 80),
      borderRadius: AppConfig.borderRadius,
    ),
  ];
}

class TutorialSequenceModel {
  final List<TutorialEnum> tutorials;

  const TutorialSequenceModel({required this.tutorials});
}
