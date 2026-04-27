import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_constants.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_widget.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_sequences.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_state_transition_events.dart';
import 'package:fluffychat/widgets/matrix.dart';

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

class TutorialOverlayController {
  late final TutorialOverlayStateMachine _state;

  TutorialOverlayController(TutorialSequence sequence) {
    final enabledSequence = TutorialSequences.enabledTutorialsInSequence(
      sequence,
    );
    _state = TutorialOverlayStateMachine(
      enabledSequence,
      initialStepIndex: enabledSequence.isNotEmpty
          ? enabledSequence[0].stepProgress
          : 0,
    );
  }

  final StreamController<TutorialEnum?> _forwardTutorialStreamController =
      StreamController<TutorialEnum?>.broadcast();

  final StreamController<TutorialEnum?> _backNavigationStreamController =
      StreamController<TutorialEnum?>.broadcast();

  Stream<TutorialEnum?> get forwardTutorialStream =>
      _forwardTutorialStreamController.stream;

  Stream<TutorialEnum?> get backNavigationStream =>
      _backNavigationStreamController.stream;

  TutorialOverlayStateMachine get state => _state;

  bool isTutorialQueued(TutorialEnum tutorial) =>
      _state.tutorialType == tutorial;

  void dispose() {
    _forwardTutorialStreamController.close();
    _backNavigationStreamController.close();
    _state.dispose();
    _closeOverlay();
  }

  void launchTutorial({
    required BuildContext context,
    required TutorialModel tutorial,
    required String? currentRoute,
  }) {
    if (!tutorial.tutorialType.locallyEnabled(currentRoute)) {
      Logs().w(
        "Tutorial ${tutorial.tutorialType} is not locally enabled for route $currentRoute",
      );
      return;
    }

    if (!isTutorialQueued(tutorial.tutorialType)) {
      Logs().w(
        "Tutorial ${tutorial.tutorialType} is not queued to launch next",
      );
      return;
    }

    if (_state.model.activeTutorial != null) {
      Logs().w(
        "Another tutorial is already active: ${_state.model.activeTutorial!.tutorialType}",
      );
      return;
    }

    final opened = _openTutorialOverlay(context);
    if (!opened) {
      return;
    }

    _state.dispatch(LaunchTutorialEvent(tutorial));
  }

  bool _openTutorialOverlay(BuildContext context) {
    if (MatrixState.pAnyState.isOverlayOpen(
      overlayKey: TutorialConstants.sequenceOverlayKey,
    )) {
      return true;
    }

    // Open the persistent sequence overlay once for the entire sequence.
    // Subsequent tutorials in the sequence reuse this overlay so that the
    // blocking dark layer is never removed between steps.
    final entry = OverlayEntry(
      builder: (overlayContext) {
        return ListenableBuilder(
          listenable: state,
          builder: (context, _) => TutorialOverlayWidget(
            model: state.model,
            forward: forwardTutorial,
            back: backTutorial,
            reset: resetTutorial,
            setTutorialTransitioning: setTutorialTransitioning,
            enabledForward: state.canGoForward,
            enabledBack: state.canGoBack,
            completedSteps:
                state.completedStepsOffset + state.model.stepIndex + 1,
            totalSteps: state.totalStepsInSequence,
          ),
        );
      },
    );

    return MatrixState.pAnyState.openOverlay(
      entry,
      context,
      rootOverlay: true,
      overlayKey: TutorialConstants.sequenceOverlayKey,
      canPop: false,
      blockOverlay: true,
    );
  }

  void setTutorialTransitioning(bool isTransitioning) =>
      _state.dispatch(TutorialTransitionEvent(isTransitioning));

  void forwardTutorial() {
    final couldGoForward = _state.canGoForward;

    final previousType = _state.tutorialType;
    final previousStepIndex = _state.model.stepIndex;

    previousType?.saveProgress(previousStepIndex + 1);
    GoogleAnalytics.completeTutorialStep(previousType!, previousStepIndex);

    _state.dispatch(ForwardTutorialEvent());
    final updatedType = _state.tutorialType;

    if (!couldGoForward) {
      resetTutorial();
      return;
    }

    if (previousType != updatedType) {
      _forwardTutorialStreamController.add(updatedType);
    }
  }

  // /// Signals the previous tutorial in the sequence to re-open at its last step.
  void backTutorial() {
    if (!state.canGoBack) {
      resetTutorial();
      return;
    }

    final previousType = _state.tutorialType;
    _state.dispatch(BackTutorialEvent());
    final updatedType = _state.tutorialType;

    if (previousType != updatedType) {
      _backNavigationStreamController.add(updatedType);
    }
  }

  void resetTutorial() {
    _state.dispatch(ResetTutorialEvent());
    _closeOverlay();
  }

  void _closeOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MatrixState.pAnyState.closeOverlay(TutorialConstants.sequenceOverlayKey);
    });
  }
}
