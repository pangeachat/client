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

  /// The saved resume step for a tutorial, consulted when the sequence crosses
  /// into it — so a learner who abandoned mid-tutorial resumes where they left
  /// off even when an earlier tutorial of the sequence ran first. Without it
  /// only the sequence's FIRST tutorial ever resumed ([initialStepIndex]);
  /// every later one silently restarted at step 0.
  final int Function(TutorialEnum tutorial)? resumeStepOf;

  late TutorialOverlayState _model;

  TutorialOverlayStateMachine(
    this._sequence, {
    int initialStepIndex = 0,
    this.resumeStepOf,
  }) {
    _model = TutorialOverlayState(stepIndex: initialStepIndex);
  }

  TutorialOverlayState get model => _model;

  void dispatch(TutorialStateTransitionEvent event) {
    _model = switch (event) {
      LaunchTutorialEvent() => _launch(event),
      TutorialTransitionEvent() => _setTransition(event),
      ForwardTutorialEvent() => _forward(),
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
  //        StepIndex = next tutorial's saved resume step (0 without one)
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
      final nextIndex = _model.tutorialIndex + 1;
      return _model.copyWith(
        tutorialIndex: nextIndex,
        stepIndex: nextIndex < _sequence.length ? _resumeStepFor(nextIndex) : 0,
        resetActiveTutorial: true,
      );
    }

    return _model.copyWith(stepIndex: _model.stepIndex + 1);
  }

  int _resumeStepFor(int tutorialIndex) {
    final tutorial = _sequence[tutorialIndex];
    final saved = resumeStepOf?.call(tutorial) ?? 0;
    // Clamped: a stale save past the end (a step removed in an update) must
    // not strand the tutorial on a step that no longer exists.
    return saved.clamp(0, tutorial.stepCount - 1);
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
