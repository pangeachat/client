import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_widget.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_tooltip_widget.dart';

class TutorialStepData {
  final GlobalKey anchor;
  final Future<void> Function()? onTap;

  TutorialStepData({required this.anchor, this.onTap});
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
            targetKey: data[0].anchor,
            tooltip: TutorialTooltipWidget(
              text: "Click on message bubble to select them",
            ),
            tooltipSize: Size(200, 60),
            onTap: data[0].onTap,
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
            targetKey: data[0].anchor,
            tooltip: TutorialTooltipWidget(
              text: "This is the input bar, where you can write your messages",
            ),
            tooltipSize: Size(200, 60),
            onTap: data[0].onTap,
          ),
          TutorialStep(
            targetKey: data[1].anchor,
            tooltip: TutorialTooltipWidget(
              text: "Click this button to open the writing assistance",
            ),
            tooltipSize: Size(200, 60),
            onTap: data[1].onTap,
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
            targetKey: data[0].anchor,
            tooltip: TutorialTooltipWidget(
              text: "Click here to translate the message",
            ),
            tooltipSize: Size(200, 60),
            onTap: data[0].onTap,
          ),
          TutorialStep(
            targetKey: data[1].anchor,
            tooltip: TutorialTooltipWidget(
              text: "Click here to listen to the message",
            ),
            tooltipSize: Size(200, 60),
            onTap: data[1].onTap,
          ),
          TutorialStep(
            targetKey: data[2].anchor,
            tooltip: TutorialTooltipWidget(
              text: "Click the background to go back to chatting",
            ),
            tooltipSize: Size(200, 60),
            onTap: data[2].onTap,
          ),
        ],
      );
}
