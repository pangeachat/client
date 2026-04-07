import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_widget.dart';
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

sealed class TutorialModel {
  final TutorialEnum tutorialType;
  final List<TutorialStep> steps;

  const TutorialModel({required this.tutorialType, required this.steps});
}

class ReadingAssistantTutorialModel extends TutorialModel {
  ReadingAssistantTutorialModel({required List<TutorialStepData> data})
    : assert(data.length == 1),
      super(
        tutorialType: TutorialEnum.readingAssistance,
        steps: [
          TutorialStep(
            targetLink: data[0].targetLink,
            targetKey: data[0].targetKey,
            onTap: data[0].onTap,
            tooltip: TutorialTooltipWidget(
              text: "Click on message bubble to select them",
            ),
            tooltipSize: Size(200, 120),
            borderRadius: AppConfig.borderRadius,
          ),
        ],
      );
}

class WritingAssistantTutorialModel extends TutorialModel {
  WritingAssistantTutorialModel({required List<TutorialStepData> data})
    : assert(data.length == 2),
      super(
        tutorialType: TutorialEnum.writingAssistance,
        steps: [
          TutorialStep(
            targetLink: data[0].targetLink,
            targetKey: data[0].targetKey,
            onTap: data[0].onTap,
            tooltip: TutorialTooltipWidget(
              text:
                  "You can write in any language. Don't worry about mistakes! We'll help you correct them.",
            ),
            tooltipSize: Size(300, 120),
            borderRadius: 24.0,
          ),
          TutorialStep(
            targetLink: data[1].targetLink,
            targetKey: data[1].targetKey,
            onTap: data[1].onTap,
            tooltip: TutorialTooltipWidget(
              text:
                  "After writing your message, click this button to start writing assistance",
            ),
            tooltipSize: Size(300, 120),
            borderRadius: 100.0,
            padding: 4.0,
          ),
        ],
      );
}

class SelectModeButtonsTutorialModel extends TutorialModel {
  SelectModeButtonsTutorialModel({required List<TutorialStepData> data})
    : assert(data.length == 3),
      super(
        tutorialType: TutorialEnum.selectModeButtons,
        steps: [
          TutorialStep(
            targetLink: data[0].targetLink,
            targetKey: data[0].targetKey,
            onTap: data[0].onTap,
            tooltip: TutorialTooltipWidget(
              text: "Click here to translate the message",
            ),
            tooltipSize: Size(200, 120),
            borderRadius: 100.0,
            padding: 0.0,
          ),
          TutorialStep(
            targetLink: data[1].targetLink,
            targetKey: data[1].targetKey,
            onTap: data[1].onTap,
            tooltip: TutorialTooltipWidget(
              text: "Click here to listen to the message",
            ),
            tooltipSize: Size(200, 120),
            borderRadius: 100.0,
            padding: 0.0,
          ),
          TutorialStep(
            targetLink: data[2].targetLink,
            targetKey: data[2].targetKey,
            onTap: data[2].onTap,
            tooltip: TutorialTooltipWidget(
              text: "Click the background to go back to chatting",
            ),
            tooltipSize: Size(200, 120),
            borderRadius: AppConfig.borderRadius,
          ),
        ],
      );
}
