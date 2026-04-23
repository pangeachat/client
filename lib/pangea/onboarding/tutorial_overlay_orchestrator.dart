import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/onboarding/tutorial_constants.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_widget.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_state_transition_events.dart';
import 'package:fluffychat/widgets/matrix.dart';

class TutorialOverlayState {
  /// The current tutorial sequence being processed, if any. Tutorials are held in the queue
  /// until activated by some trigger within the app (i.e. opening message toolbar)
  final TutorialSequence? sequence;

  /// The index of the current tutorial in the sequence.
  final int activeTutorialIndex;

  /// The current tutorial model
  final TutorialModel? activeTutorial;

  /// True while a tutorial step's [TutorialStepData.onTap] callback is being executed
  final bool isStepTransitioning;

  const TutorialOverlayState({
    this.sequence,
    this.activeTutorialIndex = -1,
    this.activeTutorial,
    this.isStepTransitioning = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'sequence': sequence?.map((t) => t.name).toList(),
      'activeTutorialIndex': activeTutorialIndex,
      'activeTutorial': activeTutorial?.tutorialType.name,
      'isStepTransitioning': isStepTransitioning,
    };
  }

  TutorialOverlayState copyWith({
    TutorialSequence? sequence,
    int? activeTutorialIndex,
    TutorialModel? activeTutorial,
    bool? isStepTransitioning,
    bool resetActiveTutorial = false,
    bool resetSequence = false,
  }) {
    return TutorialOverlayState(
      sequence: resetSequence ? null : (sequence ?? this.sequence),
      activeTutorialIndex: activeTutorialIndex ?? this.activeTutorialIndex,
      activeTutorial: resetActiveTutorial
          ? null
          : (activeTutorial ?? this.activeTutorial),
      isStepTransitioning: isStepTransitioning ?? this.isStepTransitioning,
    );
  }
}

class TutorialOverlayStateMachine extends ChangeNotifier {
  TutorialOverlayState model = const TutorialOverlayState();

  void dispatch(TutorialStateTransitionEvent event) {
    model = switch (event) {
      EnqueueSequenceEvent(:final sequence) => _enqueue(sequence),
      LaunchTutorialEvent(:final tutorial) => _launch(tutorial),
      PreviousTutorialEvent() => _previous(),
      BeginStepTransitionEvent() => _beginTransition(),
      EndStepTransitionEvent() => _endTransition(),
      CloseTutorialEvent() => _finishTutorial(),
      ResetSequenceEvent() => _resetSequence(),
    };
    notifyListeners();
  }

  TutorialOverlayState _enqueue(TutorialSequence tutorialSequence) {
    if (model.sequence != null) return model;
    return TutorialOverlayState(sequence: tutorialSequence);
  }

  TutorialOverlayState _launch(TutorialModel tutorial) {
    if (model.sequence == null) return model;
    final updatedIndex = model.activeTutorialIndex + 1;
    return model.copyWith(
      activeTutorialIndex: updatedIndex,
      activeTutorial: tutorial,
    );
  }

  TutorialOverlayState _previous() {
    final updatedIndex = model.activeTutorialIndex - 1;
    if (model.sequence == null || updatedIndex < 0) return model;

    return model.copyWith(
      activeTutorialIndex: updatedIndex,
      resetActiveTutorial: true,
    );
  }

  TutorialOverlayState _beginTransition() =>
      model.copyWith(isStepTransitioning: true);

  TutorialOverlayState _endTransition() =>
      model.copyWith(isStepTransitioning: false);

  TutorialOverlayState _finishTutorial() =>
      model.copyWith(resetActiveTutorial: true);

  TutorialOverlayState _resetSequence() => const TutorialOverlayState();
}

class TutorialOverlayController {
  TutorialOverlayController._();

  static final TutorialOverlayController instance =
      TutorialOverlayController._();

  final _state = TutorialOverlayStateMachine();

  final ValueNotifier<TutorialEnum?> closedTutorialNotifier = ValueNotifier(
    null,
  );

  final ValueNotifier<TutorialEnum?> backNavigationNotifier = ValueNotifier(
    null,
  );

  bool get hasPreviousTutorial =>
      _state.model.sequence != null &&
      _state.model.activeTutorialIndex > 0 &&
      _state.model.activeTutorialIndex < _state.model.sequence!.length;

  bool get isSequenceComplete =>
      _state.model.sequence != null &&
      _state.model.activeTutorialIndex == _state.model.sequence!.length - 1;

  int get totalStepsInCurrentSequence {
    final sequence = _state.model.sequence;
    if (sequence == null) return 0;
    return sequence.fold(0, (sum, tutorial) => sum + tutorial.stepCount);
  }

  int get completedStepsOffset {
    final sequence = _state.model.sequence;
    if (sequence == null || _state.model.activeTutorialIndex < 0) return 0;
    return sequence
        .take(_state.model.activeTutorialIndex)
        .fold(0, (sum, tutorial) => sum + tutorial.stepCount);
  }

  bool get isStepTransitioning => _state.model.isStepTransitioning;

  bool isTutorialQueued(TutorialEnum tutorial) {
    final sequence = _state.model.sequence;
    if (sequence == null) return false;

    final nextIndex = _state.model.activeTutorialIndex + 1;
    if (nextIndex >= sequence.length) return false;
    return sequence[nextIndex] == tutorial;
  }

  bool isTutorialActive(TutorialEnum tutorial) =>
      _state.model.activeTutorial?.tutorialType == tutorial;

  bool hasCompletedTutorialSequence(TutorialSequence tutorialSequence) =>
      _enabledTutorialsInSequence(tutorialSequence).isEmpty;

  List<TutorialEnum> _enabledTutorialsInSequence(
    TutorialSequence tutorialSequence,
  ) => tutorialSequence.where((t) => t.globallyEnabled).toList();

  void dispose() {
    resetState();
    closedTutorialNotifier.dispose();
    backNavigationNotifier.dispose();
    _state.dispose();
  }

  /// Adds a single tutorial sequence to the end of the queue.
  void enqueueTutorialSequence(TutorialSequence tutorialSequence) {
    if (_state.model.sequence != null) {
      return;
    }

    final enabledTutorials = _enabledTutorialsInSequence(tutorialSequence);
    if (enabledTutorials.isEmpty) {
      return;
    }

    _state.dispatch(EnqueueSequenceEvent(enabledTutorials));
  }

  void launchNextTutorial({
    required BuildContext context,
    required TutorialModel tutorial,
    required String? currentRoute,
    int initialStepIndex = 0,
  }) {
    if (!tutorial.tutorialType.locallyEnabled(currentRoute)) {
      return;
    }

    if (!isTutorialQueued(tutorial.tutorialType)) {
      return;
    }

    if (_state.model.activeTutorial != null) {
      return;
    }

    final opened = _openTutorialOverlay(context, stepIndex: initialStepIndex);
    if (!opened) {
      return;
    }

    _state.dispatch(LaunchTutorialEvent(tutorial));
  }

  bool _openTutorialOverlay(BuildContext context, {int stepIndex = 0}) {
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
          listenable: _state,
          builder: (context, _) {
            final value = _state.model.activeTutorial;
            if (value == null) {
              // Between tutorials: block all interaction without showing UI.
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
              );
            }
            return TutorialOverlayWidget(
              key: ValueKey(value.tutorialType),
              tutorial: value,
              initialStepIndex: stepIndex,
            );
          },
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

  void beginStepTransition() => _state.dispatch(BeginStepTransitionEvent());

  void endStepTransition() => _state.dispatch(EndStepTransitionEvent());

  /// Signals the previous tutorial in the sequence to re-open at its last step.
  void launchPreviousTutorial() {
    if (!hasPreviousTutorial) {
      _closeOverlay();
      return;
    }

    final updatedIndex = _state.model.activeTutorialIndex - 1;
    final previousTutorialEnum = _state.model.sequence![updatedIndex];
    _state.dispatch(PreviousTutorialEvent());

    // Defer the stream emission to the next frame so that the closing widget's
    // dispose → onCloseTutorial runs before host widgets try to launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      backNavigationNotifier.value = previousTutorialEnum;
    });
  }

  void completeTutorial(TutorialEnum tutorial) {
    if (!isTutorialActive(tutorial)) return;
    _closeTutorial(completed: true);
  }

  void handleUnexpectedClose({bool completed = false}) {
    _closeTutorial(completed: completed);
  }

  void _closeTutorial({bool completed = true}) {
    final wasFinal = isSequenceComplete;
    final tutorialType = _state.model.activeTutorial?.tutorialType;

    _state.dispatch(CloseTutorialEvent());

    if (completed) tutorialType?.markSeen();
    closedTutorialNotifier.value = tutorialType;

    if (wasFinal) {
      _closeOverlay();
    }
  }

  /// Cancels the active tutorial and the whole sequence, immediately closing the persistent overlay.
  void cancelSequence() {
    final tutorial = _state.model.activeTutorial?.tutorialType;
    _closeOverlay();
    resetState();

    if (tutorial != null) {
      closedTutorialNotifier.value = tutorial;
    }
  }

  void resetState() {
    _state.dispatch(ResetSequenceEvent());
  }

  void _closeOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MatrixState.pAnyState.closeOverlay(TutorialConstants.sequenceOverlayKey);
    });
  }
}
