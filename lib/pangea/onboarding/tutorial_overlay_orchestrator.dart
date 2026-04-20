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

  final StreamController<TutorialEnum> _tutorialNavigationStreamController =
      StreamController.broadcast();

  final StreamController<TutorialEnum> _goBackTutorialStreamController =
      StreamController.broadcast();

  TutorialEnum? _activeTutorial;
  TutorialSequenceModel? _sequence;
  int _index = 0;

  /// Set by [requestGoBack] to the last step of the previous tutorial. Consumed
  /// (and cleared) by the next [launchTutorial] call so that callers which don't
  /// know about the go-back (e.g. [SelectModeButtonsState.initState]) still
  /// start at the correct step.
  int? _pendingInitialStepIndex;

  Stream<TutorialEnum> get tutorialNavigationStream =>
      _tutorialNavigationStreamController.stream;

  /// Emits the [TutorialEnum] of the tutorial the user navigated back to.
  /// Host widgets should listen to this, re-prepare their UI state, and
  /// call [launchTutorial] with [initialStepIndex] set to the last step.
  Stream<TutorialEnum> get goBackTutorialStream =>
      _goBackTutorialStreamController.stream;

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
        .take(_index - 1)
        .fold(0, (sum, tutorial) => sum + tutorial.stepCount);
  }

  /// Returns true if [tutorial] is the next tutorial to be opened from the queue.
  bool isTutorialQueued(TutorialEnum tutorial) {
    final sequence = _sequence;
    if (sequence == null) return false;
    if (_index >= sequence.tutorials.length) return false;

    return sequence.tutorials[_index] == tutorial;
  }

  bool hasCompletedTutorialSequence(TutorialSequenceModel tutorialSequence) =>
      unseenTutorialsInSequence(tutorialSequence).isEmpty;

  List<TutorialEnum> unseenTutorialsInSequence(
    TutorialSequenceModel tutorialSequence,
  ) => tutorialSequence.tutorials.where((t) => !t.hasBeenSeen).toList();

  /// Adds a single tutorial sequence to the end of the queue.
  void enqueueTutorialSequence(TutorialSequenceModel tutorialSequence) {
    if (_sequence != null) {
      Logs().w(
        "Trying to enqueue tutorial sequence while previous sequence is still active",
      );
      return;
    }

    final unseenTutorials = unseenTutorialsInSequence(tutorialSequence);
    if (unseenTutorials.isEmpty) {
      Logs().i("All tutorials in sequence have already been seen, skipping");
      return;
    }

    Logs().w("Enqueuing tutorial sequence with tutorials $unseenTutorials");

    _sequence = TutorialSequenceModel(tutorials: unseenTutorials);
    _index = 0;
  }

  void launchTutorial({
    required BuildContext context,
    required TutorialModel tutorial,
    int initialStepIndex = 0,
  }) {
    Logs().i("Attempting to launch tutorial ${tutorial.tutorialType}");

    if (!isTutorialQueued(tutorial.tutorialType)) {
      Logs().w("Tutorial ${tutorial.tutorialType} is not next in queue");
      return;
    }

    if (_activeTutorial != null) {
      Logs().w("Tutorial $_activeTutorial already open");
    }

    // _pendingInitialStepIndex is set by requestGoBack for callers that don't
    // know they need to start at a non-zero step (e.g. SelectModeButtons).
    final effectiveIndex = _pendingInitialStepIndex ?? initialStepIndex;
    _pendingInitialStepIndex = null;

    final entry = OverlayEntry(
      builder: (context) {
        return TutorialOverlayWidget(
          tutorial: tutorial,
          initialStepIndex: effectiveIndex,
        );
      },
    );

    final success = MatrixState.pAnyState.openOverlay(
      entry,
      context,
      rootOverlay: true,
      overlayKey: tutorial.tutorialType.name,
      canPop: false,
      blockOverlay: true,
    );

    if (!success) {
      Logs().e("Failed to open tutorial overlay for ${tutorial.tutorialType}");
      return;
    }

    _activeTutorial = tutorial.tutorialType;
    _index++;
  }

  void closeTutorial({required TutorialModel tutorial}) {
    MatrixState.pAnyState.closeOverlay(tutorial.tutorialType.name);
  }

  /// Returns true if there is a previous tutorial in the sequence that the
  /// user could navigate back to from the given [tutorial].
  bool hasPreviousTutorial(TutorialEnum tutorial) {
    if (_sequence == null) return false;
    // _index is "next to launch"; the active tutorial is at _index - 1.
    // A previous tutorial exists at _index - 2.
    return _index >= 2;
  }

  /// Signals the previous tutorial in the sequence to re-open at its last step.
  ///
  /// The [currentTutorial]'s overlay is closed. After the next frame (so
  /// [onCloseTutorial] has had time to run), [goBackTutorialStream] emits the
  /// enum of the tutorial to re-open. Host widgets should listen, restore any
  /// required UI state, then call [launchTutorial] with
  /// `initialStepIndex: tutorialType.stepCount - 1`.
  void requestGoBack({required TutorialModel currentTutorial}) {
    if (!hasPreviousTutorial(currentTutorial.tutorialType)) return;

    // Decrement by 2: undo the last launch increment, then step back one more
    // so that after the previous tutorial calls launchTutorial (which does
    // _index++) the index is back to _index - 1.
    _index -= 2;
    final previousTutorialEnum = _sequence!.tutorials[_index];
    _pendingInitialStepIndex = previousTutorialEnum.stepCount - 1;

    closeTutorial(tutorial: currentTutorial);

    // Defer the stream emission to the next frame so that the closing widget's
    // dispose → onCloseTutorial runs before host widgets try to launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _goBackTutorialStreamController.add(previousTutorialEnum);
    });
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

    // Only clear _activeTutorial if it still matches this tutorial — a
    // requestGoBack() may have already set it to a newly launched model.
    if (_activeTutorial == tutorial) {
      _activeTutorial = null;
    }
    _tutorialNavigationStreamController.add(tutorial);
  }
}
