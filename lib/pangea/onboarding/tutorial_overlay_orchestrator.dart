import 'package:fluffychat/pangea/onboarding/tutorial_constants.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_widget.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_state_transition_events.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';

class _TutorialOverlayState {
  /// The current tutorial sequence being processed, if any. Tutorials are held in the queue
  /// until activated by some trigger within the app (i.e. opening message toolbar)
  final TutorialSequence? sequence;

  /// The index of the current tutorial in the sequence.
  final int activeTutorialIndex;

  /// The current tutorial model
  final TutorialModel? activeTutorial;

  /// True while a tutorial step's [TutorialStepData.onTap] callback is being executed
  final bool isStepTransitioning;

  const _TutorialOverlayState({
    this.sequence,
    this.activeTutorialIndex = -1,
    this.activeTutorial,
    this.isStepTransitioning = false,
  });
}

class _TutorialOverlayStateMachine extends ChangeNotifier {
  _TutorialOverlayState _model = const _TutorialOverlayState();

  bool get hasQueuedTutorial => _model.sequence != null;

  bool get hasActiveTutorial => _model.activeTutorial != null;

  bool get hasPreviousTutorial =>
      _model.sequence != null &&
      _model.activeTutorialIndex > 0 &&
      _model.activeTutorialIndex < _model.sequence!.length;

  bool get isStepTransitioning => _model.isStepTransitioning;

  bool get isSequenceComplete =>
      _model.sequence != null &&
      _model.activeTutorialIndex == _model.sequence!.length - 1;

  TutorialModel? get activeTutorial => _model.activeTutorial;

  int get totalStepsInCurrentSequence {
    final sequence = _model.sequence;
    if (sequence == null) return 0;
    return sequence.fold(0, (sum, tutorial) => sum + tutorial.stepCount);
  }

  int get completedStepsOffset {
    final sequence = _model.sequence;
    if (sequence == null || _model.activeTutorialIndex < 0) return 0;
    return sequence
        .take(_model.activeTutorialIndex)
        .fold(0, (sum, tutorial) => sum + tutorial.stepCount);
  }

  bool isTutorialQueued(TutorialEnum tutorial) {
    final sequence = _model.sequence;
    if (sequence == null) return false;

    final nextIndex = _model.activeTutorialIndex + 1;
    if (nextIndex >= sequence.length) return false;
    return sequence[nextIndex] == tutorial;
  }

  bool isTutorialActive(TutorialEnum tutorial) =>
      _model.activeTutorial?.tutorialType == tutorial;

  void dispatch(TutorialStateTransitionEvent event) {
    _model = switch (event) {
      EnqueueSequenceEvent(:final sequence) => enqueue(sequence),
      LaunchTutorialEvent(:final tutorial) => launch(tutorial),
      PreviousTutorialEvent() => previous(),
      BeginStepTransitionEvent() => beginTransition(),
      EndStepTransitionEvent() => endTransition(),
      CompleteTutorialEvent() => complete(),
      ResetSequenceEvent() => const _TutorialOverlayState(),
    };
    notifyListeners();
  }

  _TutorialOverlayState enqueue(TutorialSequence tutorialSequence) {
    if (_model.sequence != null) {
      Logs().w(
        "Tried to enqueue tutorial sequence while another sequence is active",
      );
      return _model;
    }

    return _TutorialOverlayState(
      sequence: tutorialSequence,
      activeTutorialIndex: -1,
      activeTutorial: null,
      isStepTransitioning: false,
    );
  }

  _TutorialOverlayState launch(TutorialModel tutorial) {
    final updatedIndex = _model.activeTutorialIndex + 1;
    if (_model.sequence == null) {
      Logs().w("Tried to launch tutorial while no sequence is active");
      return _model;
    }

    return _TutorialOverlayState(
      sequence: _model.sequence,
      activeTutorialIndex: updatedIndex,
      activeTutorial: tutorial,
      isStepTransitioning: false,
    );
  }

  _TutorialOverlayState previous() {
    final updatedIndex = _model.activeTutorialIndex - 1;
    if (_model.sequence == null || updatedIndex < 0) return _model;

    return _TutorialOverlayState(
      sequence: _model.sequence,
      activeTutorialIndex: updatedIndex,
      activeTutorial: null,
      isStepTransitioning: false,
    );
  }

  _TutorialOverlayState beginTransition() {
    return _TutorialOverlayState(
      sequence: _model.sequence,
      activeTutorialIndex: _model.activeTutorialIndex,
      activeTutorial: _model.activeTutorial,
      isStepTransitioning: true,
    );
  }

  _TutorialOverlayState endTransition() {
    return _TutorialOverlayState(
      sequence: _model.sequence,
      activeTutorialIndex: _model.activeTutorialIndex,
      activeTutorial: _model.activeTutorial,
      isStepTransitioning: false,
    );
  }

  _TutorialOverlayState complete() {
    return _TutorialOverlayState(
      sequence: _model.sequence,
      activeTutorialIndex: _model.activeTutorialIndex,
      activeTutorial: null,
      isStepTransitioning: false,
    );
  }
}

class TutorialOverlayOrchestrator {
  TutorialOverlayOrchestrator._();

  static final TutorialOverlayOrchestrator instance =
      TutorialOverlayOrchestrator._();

  final _state = _TutorialOverlayStateMachine();

  final ValueNotifier<TutorialEnum?> closedTutorialNotifier = ValueNotifier(
    null,
  );

  final ValueNotifier<TutorialEnum?> backNavigationNotifier = ValueNotifier(
    null,
  );

  bool get isStepTransitioning => _state.isStepTransitioning;

  bool get hasActiveTutorial => _state.hasActiveTutorial;

  bool get hasPreviousTutorial => _state.hasPreviousTutorial;

  int get totalStepsInCurrentSequence => _state.totalStepsInCurrentSequence;

  int get completedStepsOffset => _state.completedStepsOffset;

  bool isTutorialQueued(TutorialEnum tutorial) =>
      _state.isTutorialQueued(tutorial);

  bool isTutorialActive(TutorialEnum tutorial) =>
      _state.isTutorialActive(tutorial);

  void dispose() {
    reset();
    closedTutorialNotifier.dispose();
    backNavigationNotifier.dispose();
    _state.dispose();
  }

  void reset() {
    MatrixState.pAnyState.closeOverlay(TutorialConstants.sequenceOverlayKey);
    _state.reset();
  }

  void beginStepTransition() => _state.beginStepTransition();
  void endStepTransition() => _state.endStepTransition();

  bool hasCompletedTutorialSequence(TutorialSequence tutorialSequence) =>
      enabledTutorialsInSequence(tutorialSequence).isEmpty;

  List<TutorialEnum> enabledTutorialsInSequence(
    TutorialSequence tutorialSequence,
  ) => tutorialSequence.where((t) => t.globallyEnabled).toList();

  /// Adds a single tutorial sequence to the end of the queue.
  void enqueueTutorialSequence(TutorialSequence tutorialSequence) {
    final enabledTutorials = enabledTutorialsInSequence(tutorialSequence);
    if (enabledTutorials.isEmpty) {
      Logs().i("All tutorials in sequence are disabled, skipping");
      return;
    }

    Logs().i("Enqueuing tutorial sequence with tutorials $enabledTutorials");
    _state.enqueueTutorialSequence(enabledTutorials);
  }

  void launchTutorial({
    required BuildContext context,
    required TutorialModel tutorial,
    required String? currentRoute,
    int initialStepIndex = 0,
  }) {
    Logs().i("Attempting to launch tutorial ${tutorial.tutorialType}");
    if (!tutorial.tutorialType.locallyEnabled(currentRoute)) {
      Logs().w("Tutorial ${tutorial.tutorialType} is not locally enabled");
      return;
    }

    if (!_state.isTutorialQueued(tutorial.tutorialType)) {
      Logs().w("Tutorial ${tutorial.tutorialType} is not next in queue");
      return;
    }

    if (_state.hasActiveTutorial) {
      Logs().w("Tutorial ${_state.activeTutorial?.tutorialType} already open");
    }

    final opened = _openTutorialOverlay(context, stepIndex: initialStepIndex);
    if (!opened) {
      Logs().e(
        "Failed to open tutorial overlay for tutorial ${tutorial.tutorialType}",
      );
      return;
    }

    _state.setActiveTutorial(tutorial);
  }

  bool _openTutorialOverlay(BuildContext context, {int stepIndex = 0}) {
    if (MatrixState.pAnyState.isOverlayOpen(
      overlayKey: TutorialConstants.sequenceOverlayKey,
    )) {
      Logs().i("Tutorial overlay is already open");
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
            final value = _state.activeTutorial;
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

  /// Signals the previous tutorial in the sequence to re-open at its last step.
  void requestGoBack() {
    final previousTutorialEnum = _state.requestGoBack();
    if (previousTutorialEnum == null) {
      Logs().i("No previous tutorial to go back to, closing overlay");
      _closeOverlay();
      return;
    }

    // Defer the stream emission to the next frame so that the closing widget's
    // dispose → onCloseTutorial runs before host widgets try to launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      backNavigationNotifier.value = previousTutorialEnum;
    });
  }

  void clearActiveTutorial(TutorialEnum tutorial) {
    if (!_state.isTutorialActive(tutorial)) {
      Logs().w(
        "Trying to clear active tutorial $tutorial but it is not currently active",
      );
      return;
    }
    _state.clearActiveTutorial(tutorial);
    closedTutorialNotifier.value = tutorial;
  }

  /// Cancels the active tutorial and the whole sequence, immediately closing
  /// the persistent overlay. Use this when a host widget is unexpectedly
  /// disposed while a tutorial is active (e.g., the user navigated away from
  /// the chat room), as opposed to [clearActiveTutorial] which is for natural
  /// step-by-step completion.
  void cancelTutorial() {
    Logs().i("Cancelling tutorial and clearing entire sequence");
    final tutorial = _state.activeTutorial?.tutorialType;
    _closeOverlay();
    reset();

    if (tutorial != null) {
      closedTutorialNotifier.value = tutorial;
    }
  }

  void onCloseTutorial(TutorialEnum tutorial, {bool completed = false}) {
    final wasFinal = _state.isSequenceComplete;
    final tutorialType = _state.activeTutorial?.tutorialType;

    _state.onCloseTutorial();

    // Only mark the tutorial fully seen when all steps were completed.
    // A mid-tutorial close preserves the saved step progress so the user
    // can resume from where they left off.
    if (completed && wasFinal) {
      tutorial.markSeen();
    }
    closedTutorialNotifier.value = tutorialType;
  }

  void _closeOverlay() {
    // Defer the actual overlay removal to avoid removing the overlay entry
    // while we are still in the middle of a widget rebuild/dispose.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MatrixState.pAnyState.closeOverlay(TutorialConstants.sequenceOverlayKey);
    });
  }
}
