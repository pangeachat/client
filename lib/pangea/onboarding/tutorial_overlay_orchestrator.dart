import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TutorialOverlayOrchestrator {
  TutorialOverlayOrchestrator._();

  static final TutorialOverlayOrchestrator instance =
      TutorialOverlayOrchestrator._();

  final StreamController<TutorialEnum> _tutorialCompleteStreamController =
      StreamController.broadcast();

  TutorialEnum? _currentTutorial;
  TutorialEnum? _nextTutorial;

  Stream<TutorialEnum> get tutorialCompleteStream =>
      _tutorialCompleteStreamController.stream;

  void dispose() {
    _tutorialCompleteStreamController.close();
  }

  void openTutorial({
    required BuildContext context,
    required TutorialEnum tutorial,
    required List<TutorialStepWidgetData> stepData,
  }) {
    List<TutorialStep> steps;
    try {
      steps = tutorial.steps(stepData);
    } catch (e, st) {
      Logs().e("Error building tutorial steps for tutorial $tutorial", e, st);
      return;
    }

    final entry = OverlayEntry(
      builder: (context) {
        return TutorialOverlayWidget(tutorial: tutorial, steps: steps);
      },
    );

    if (_currentTutorial != null) {
      Logs().w(
        "Trying to open tutorial with key $tutorial while tutorial with key $_currentTutorial is still open",
      );
    } else {
      Logs().i(
        "Opening tutorial with key $tutorial. Current tutorial is $_currentTutorial",
      );
    }

    _currentTutorial = tutorial;
    MatrixState.pAnyState.openOverlay(
      entry,
      context,
      rootOverlay: true,
      overlayKey: tutorial.name,
      canPop: false,
      blockOverlay: true,
    );
  }

  void closeTutorial({required TutorialEnum tutorial}) {
    if (_currentTutorial != tutorial) {
      Logs().w(
        "Trying to close tutorial with key $tutorial but current tutorial is $_currentTutorial",
      );
    }
    MatrixState.pAnyState.closeOverlay(tutorial.name);
  }

  void onCloseTutorial(TutorialEnum tutorial) {
    if (_currentTutorial == tutorial) {
      _currentTutorial = null;
    } else {
      Logs().w(
        "Trying to close tutorial with key $tutorial but current tutorial is $_currentTutorial",
      );
    }
    _tutorialCompleteStreamController.add(tutorial);
  }

  bool isTutorialQueued(TutorialEnum tutorial) => _nextTutorial == tutorial;

  void queueTutorial(TutorialEnum tutorial) {
    _nextTutorial = tutorial;
  }

  void openQueuedTutorial({
    required BuildContext context,
    required TutorialEnum tutorial,
    required List<TutorialStepWidgetData> stepData,
  }) {
    if (tutorial != _nextTutorial) {
      Logs().w(
        "Trying to open queued tutorial with key $tutorial but next tutorial is $_nextTutorial",
      );
      return;
    }

    _nextTutorial = null;
    openTutorial(context: context, tutorial: tutorial, stepData: stepData);
  }
}
