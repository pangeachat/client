import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_state_transition_events.dart';

class TutorialOverlayState {
  /// The index next / current tutorial
  final int tutorialIndex;

  /// The step index within the current tutorial
  final int stepIndex;

  /// The current tutorial model
  final TutorialModel? activeTutorial;

  /// True while a tutorial step's [TutorialStepData.onTap] callback is being executed
  final bool isStepTransitioning;

  const TutorialOverlayState({
    this.tutorialIndex = 0,
    this.stepIndex = 0,
    this.activeTutorial,
    this.isStepTransitioning = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'tutorialIndex': tutorialIndex,
      'stepIndex': stepIndex,
      'activeTutorial': activeTutorial?.tutorialType.name,
      'isStepTransitioning': isStepTransitioning,
    };
  }

  TutorialOverlayState copyWith({
    int? tutorialIndex,
    TutorialModel? activeTutorial,
    int? stepIndex,
    bool? isStepTransitioning,
    bool resetActiveTutorial = false,
  }) {
    return TutorialOverlayState(
      tutorialIndex: tutorialIndex ?? this.tutorialIndex,
      activeTutorial: resetActiveTutorial
          ? null
          : (activeTutorial ?? this.activeTutorial),
      stepIndex: stepIndex ?? this.stepIndex,
      isStepTransitioning: isStepTransitioning ?? this.isStepTransitioning,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TutorialOverlayState &&
        other.tutorialIndex == tutorialIndex &&
        other.activeTutorial?.tutorialType == activeTutorial?.tutorialType &&
        other.stepIndex == stepIndex &&
        other.isStepTransitioning == isStepTransitioning;
  }

  @override
  int get hashCode =>
      tutorialIndex.hashCode ^
      (activeTutorial?.tutorialType).hashCode ^
      stepIndex.hashCode ^
      isStepTransitioning.hashCode;
}

class TutorialOverlayStateMachine extends ChangeNotifier {
  final TutorialSequence _sequence;
  late TutorialOverlayState _model;

  TutorialOverlayStateMachine(this._sequence, {int initialStepIndex = 0}) {
    _model = TutorialOverlayState(stepIndex: initialStepIndex);
  }

  TutorialOverlayState get model => _model;

  void dispatch(TutorialStateTransitionEvent event) {
    _model = switch (event) {
      LaunchTutorialEvent() => _launch(event),
      TutorialTransitionEvent() => _setTransition(event),
      ForwardTutorialEvent() => _forward(),
      BackTutorialEvent() => _back(),
      ResetTutorialEvent() => reset(),
    };
    notifyListeners();
  }

  // [LaunchTutorialEvent]:
  //    ActiveTutorial is set to the tutorial being launched
  TutorialOverlayState _launch(LaunchTutorialEvent event) {
    return _model.copyWith(activeTutorial: event.tutorial);
  }

  // [TransitionEvent]:
  //    IsStepTransitioning is set to true or false based on the event details
  TutorialOverlayState _setTransition(TutorialTransitionEvent event) =>
      _model.copyWith(isStepTransitioning: event.isTransitioning);

  // [ForwardEvent]:
  //    If current step index >= stepCount - 1 (reached the end of this tutorial):
  //        StepIndex = 0
  //        TutorialIndex++
  //        ActiveTutorial = null
  //
  //        If TutorialIndex >= sequence length (reached the end of the sequence):
  //            Sequence is now completed
  //
  //    Else (valid next step in active tutorial):
  //        StepIndex++
  TutorialOverlayState _forward() {
    if (_model.tutorialIndex >= _sequence.length) {
      return _model.copyWith(stepIndex: 0, resetActiveTutorial: true);
    }

    final stepCount = _sequence[_model.tutorialIndex].stepCount;
    if (_model.stepIndex >= stepCount - 1) {
      return _model.copyWith(
        tutorialIndex: _model.tutorialIndex + 1,
        stepIndex: 0,
        resetActiveTutorial: true,
      );
    }

    return _model.copyWith(stepIndex: _model.stepIndex + 1);
  }

  // [BackEvent]:
  //    If current step index <= 0 (reached the beginning of this tutorial):
  //        StepIndex = previous tutorial's step count - 1
  //        TutorialIndex--
  //        ActiveTutorial = null
  //
  //        If tutorial index <= 0 (reached the beginning of the sequence):
  //            Sequence is now at the beginning, cannot go back further
  //
  //    Else:
  //        StepIndex--
  TutorialOverlayState _back() {
    if (_model.stepIndex <= 0) {
      final updatedTutorialIndex = _model.tutorialIndex - 1;
      int updatedStepIndex = 0;
      if (updatedTutorialIndex >= 0) {
        final previousTutorial = _sequence[updatedTutorialIndex];
        updatedStepIndex = previousTutorial.stepCount - 1;
      }

      return _model.copyWith(
        tutorialIndex: updatedTutorialIndex,
        stepIndex: updatedStepIndex,
        resetActiveTutorial: true,
      );
    }

    return _model.copyWith(stepIndex: _model.stepIndex - 1);
  }

  TutorialOverlayState reset() => _model.copyWith(resetActiveTutorial: true);

  int get completedStepsOffset {
    if (_model.tutorialIndex < 0) return 0;
    return _sequence
        .take(_model.tutorialIndex)
        .fold(0, (sum, tutorial) => sum + tutorial.stepCount);
  }

  int get totalStepsInSequence {
    return _sequence.fold(0, (sum, tutorial) => sum + tutorial.stepCount);
  }

  bool get hasPreviousTutorial => _model.tutorialIndex > 0;

  bool get hasPreviousStep => _model.stepIndex > 0;

  bool get canGoBack => hasPreviousStep || hasPreviousTutorial;

  bool get hasNextTutorial => _model.tutorialIndex < _sequence.length - 1;

  bool get hasNextStep {
    final stepCount = tutorialType?.stepCount;
    if (stepCount == null) return false;
    return _model.stepIndex < stepCount - 1;
  }

  bool get canGoForward => hasNextStep || hasNextTutorial;

  bool get hasCompletedSequence => _model.tutorialIndex >= _sequence.length;

  TutorialEnum? get tutorialType {
    if (_model.tutorialIndex < 0 || _model.tutorialIndex >= _sequence.length) {
      return null;
    }
    return _sequence[_model.tutorialIndex];
  }

  bool isTutorialActive(TutorialEnum tutorial) =>
      _model.activeTutorial?.tutorialType == tutorial;
}
