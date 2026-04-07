import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/onboarding/tutorial_overlay_widget.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_tooltip_widget.dart';

class TutorialStepWidgetData {
  final GlobalKey anchor;
  final Future<void> Function()? onTap;

  TutorialStepWidgetData({required this.anchor, this.onTap});
}

enum TutorialEnum {
  readingAssistance,
  writingAssistance,
  selectModeButtons;

  List<TutorialStep> steps(List<TutorialStepWidgetData> data) {
    switch (this) {
      case TutorialEnum.readingAssistance:
        return ReadingAssistanceTutorialStepEnum.values
            .map((e) => e.stepBuilder(data))
            .toList();
      case TutorialEnum.writingAssistance:
        return WritingAssistanceTutorialStepEnum.values
            .map((e) => e.stepBuilder(data))
            .toList();
      case TutorialEnum.selectModeButtons:
        return SelectModeButtonsTutorialStepEnum.values
            .map((e) => e.stepBuilder(data))
            .toList();
    }
  }
}

enum ReadingAssistanceTutorialStepEnum {
  selectMessage;

  TutorialStep stepBuilder(List<TutorialStepWidgetData> data) {
    assert(data.length == ReadingAssistanceTutorialStepEnum.values.length);
    switch (this) {
      case ReadingAssistanceTutorialStepEnum.selectMessage:
        return TutorialStep(
          targetKey: data[0].anchor,
          tooltip: TutorialTooltipWidget(
            text: "Click on message bubble to select them",
          ),
          tooltipSize: Size(200, 60),
          onTap: data[0].onTap,
        );
    }
  }
}

enum WritingAssistanceTutorialStepEnum {
  inputBar,
  igcButton;

  TutorialStep stepBuilder(List<TutorialStepWidgetData> data) {
    assert(data.length == WritingAssistanceTutorialStepEnum.values.length);
    switch (this) {
      case WritingAssistanceTutorialStepEnum.inputBar:
        return TutorialStep(
          targetKey: data[0].anchor,
          tooltip: TutorialTooltipWidget(
            text:
                "You can write messages in any language. We'll help you write in your target language.",
          ),
          tooltipSize: Size(300, 100),
          onTap: data[0].onTap,
        );
      case WritingAssistanceTutorialStepEnum.igcButton:
        return TutorialStep(
          targetKey: data[1].anchor,
          tooltip: TutorialTooltipWidget(
            text:
                "After writing your message, click here for writing assistance.",
          ),
          tooltipSize: Size(300, 80),
          onTap: data[1].onTap,
        );
    }
  }
}

enum SelectModeButtonsTutorialStepEnum {
  translation,
  audio,
  close;

  TutorialStep stepBuilder(List<TutorialStepWidgetData> data) {
    assert(data.length == SelectModeButtonsTutorialStepEnum.values.length);
    switch (this) {
      case SelectModeButtonsTutorialStepEnum.translation:
        return TutorialStep(
          targetKey: data[0].anchor,
          tooltip: TutorialTooltipWidget(
            text: "Click here to translate the message",
          ),
          tooltipSize: Size(200, 60),
          onTap: data[0].onTap,
        );
      case SelectModeButtonsTutorialStepEnum.audio:
        return TutorialStep(
          targetKey: data[1].anchor,
          tooltip: TutorialTooltipWidget(
            text: "Click here to listen to the message",
          ),
          tooltipSize: Size(200, 60),
          onTap: data[1].onTap,
        );
      case SelectModeButtonsTutorialStepEnum.close:
        return TutorialStep(
          targetKey: data[2].anchor,
          tooltip: TutorialTooltipWidget(
            text: "Click the background to go back to chatting",
          ),
          tooltipSize: Size(200, 60),
          onTap: data[2].onTap,
        );
    }
  }
}
