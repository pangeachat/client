import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_widget.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TutorialOverlayOrchestrator {
  TutorialOverlayOrchestrator._();

  static final TutorialOverlayOrchestrator instance =
      TutorialOverlayOrchestrator._();

  final StreamController<TutorialEnum> _tutorialCompleteStreamController =
      StreamController.broadcast();

  TutorialEnum? _activeTutorial;
  TutorialSequenceModel? _sequence;
  int _index = 0;

  Stream<TutorialEnum> get tutorialCompleteStream =>
      _tutorialCompleteStreamController.stream;

  int get totalStepsInCurrentSequence {
    if (_sequence == null) return 0;
    return _sequence!.tutorials.fold(
      0,
      (sum, tutorial) => sum + tutorial.stepCount,
    );
  }

  int get completedStepsOffset {
    final sequence = _sequence;
    if (sequence == null || _index == 0) return 0;

    return sequence.tutorials
        .take(_index)
        .fold(0, (sum, tutorial) => sum + tutorial.stepCount);
  }

  /// Returns true if [tutorial] is the next tutorial to be opened from the queue.
  bool isTutorialQueued(TutorialEnum tutorial) {
    final sequence = _sequence;
    if (sequence == null) return false;
    if (_index >= sequence.tutorials.length) return false;

    return sequence.tutorials[_index] == tutorial;
  }

  /// Adds a single tutorial sequence to the end of the queue.
  void enqueueTutorialSequence(TutorialSequenceModel tutorialSequence) {
    if (_sequence != null) {
      Logs().w(
        "Trying to enqueue tutorial sequence while previous sequence is still active",
      );
      return;
    }

    Logs().w(
      "Enqueuing tutorial sequence with tutorials ${tutorialSequence.tutorials}",
    );

    _sequence = tutorialSequence;
    _index = 0;
  }

  void launchTutorial({
    required BuildContext context,
    required TutorialModel tutorial,
  }) {
    Logs().i("Attempting to launch tutorial ${tutorial.tutorialType}");

    if (!isTutorialQueued(tutorial.tutorialType)) {
      Logs().w("Tutorial ${tutorial.tutorialType} is not next in queue");
      return;
    }

    if (_activeTutorial != null) {
      Logs().w("Tutorial $_activeTutorial already open");
    }

    final entry = OverlayEntry(
      builder: (context) {
        return TutorialOverlayWidget(tutorial: tutorial);
      },
    );

    MatrixState.pAnyState.openOverlay(
      entry,
      context,
      rootOverlay: true,
      overlayKey: tutorial.tutorialType.name,
      canPop: false,
      blockOverlay: true,
    );

    _activeTutorial = tutorial.tutorialType;
    _index++;
  }

  void closeTutorial({required TutorialModel tutorial}) {
    MatrixState.pAnyState.closeOverlay(tutorial.tutorialType.name);
  }

  void onCloseTutorial(TutorialEnum tutorial) {
    if (_sequence == null) {
      Logs().w(
        "Received tutorial complete event for tutorial $tutorial but no active tutorial sequence",
      );
    } else if (_index >= _sequence!.tutorials.length) {
      Logs().i("Reached end of tutorial sequence");
      _sequence = null;
      _index = 0;
    }

    _activeTutorial = null;
    _tutorialCompleteStreamController.add(tutorial);
  }
}
