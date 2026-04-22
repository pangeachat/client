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

  /// The current tutorial sequence being processed, if any. Tutorials are held in the queue
  /// until activated by some trigger within the app (i.e. opening message toolbar)
  TutorialSequence? _sequence;

  /// The index of the next tutorial to be launched in the current sequence.
  int _index = 0;

  /// The single overlay entry key used for the entire tutorial sequence.
  /// One overlay stays open from the first tutorial through the last,
  /// preventing users from interacting with the UI in the gaps between.
  static const _sequenceOverlayKey = 'tutorial_sequence';

  /// True while a tutorial step's [TutorialStepData.onTap] callback is being
  /// executed. Host widgets that are intentionally disposed as a side-effect of
  /// a step action (e.g. closing the message overlay in the last step) can
  /// check this flag to avoid prematurely cancelling the tutorial sequence.
  bool _isStepTransitioning = false;
  bool get isStepTransitioning => _isStepTransitioning;

  void beginStepTransition() => _isStepTransitioning = true;
  void endStepTransition() => _isStepTransitioning = false;

  /// Drives the content shown inside the persistent sequence overlay.
  /// `null` between tutorials (overlay visible but no tooltip/hole shown).
  final ValueNotifier<({TutorialModel tutorial, int stepIndex})?>
  activeTutorialNotifier = ValueNotifier(null);

  final StreamController<TutorialEnum> _closedTutorialStream =
      StreamController.broadcast();

  final StreamController<TutorialEnum> _backNavigationStream =
      StreamController.broadcast();

  /// Stream controller for emitting completion events when a tutorial is completed or forcibly closed.
  /// Used to trigger sequence progression and allow host widgets to respond to tutorial completion.
  Stream<TutorialEnum> get closedTutorialStream => _closedTutorialStream.stream;

  /// Emits the [TutorialEnum] of the tutorial the user navigated back to.
  /// Host widgets should listen to this, re-prepare their UI state, and
  /// call [launchTutorial] with [initialStepIndex] set to the last step.
  Stream<TutorialEnum> get backNavigationStream => _backNavigationStream.stream;

  int get totalStepsInCurrentSequence {
    if (_sequence == null) return 0;
    return _sequence!.fold(0, (sum, tutorial) => sum + tutorial.stepCount);
  }

  int get completedStepsOffset {
    final sequence = _sequence;
    if (sequence == null || _index == 0) return 0;

    return sequence
        .take(_index - 1)
        .fold(0, (sum, tutorial) => sum + tutorial.stepCount);
  }

  bool get hasActiveTutorial => activeTutorialNotifier.value != null;

  void dispose() {
    reset();
    _closedTutorialStream.close();
    _backNavigationStream.close();
    activeTutorialNotifier.dispose();
  }

  void reset() {
    Logs().w("Resetting tutorial orchestrator state");
    MatrixState.pAnyState.closeOverlay(_sequenceOverlayKey);
    activeTutorialNotifier.value = null;
    _sequence = null;
    _index = 0;
    _isStepTransitioning = false;
  }

  /// Returns true if [tutorial] is the next tutorial to be opened from the queue.
  bool isTutorialQueued(TutorialEnum tutorial) {
    final sequence = _sequence;
    if (sequence == null) return false;
    if (_index >= sequence.length) return false;

    return sequence[_index] == tutorial;
  }

  bool isTutorialActive(TutorialEnum tutorial) =>
      activeTutorialNotifier.value?.tutorial.tutorialType == tutorial;

  bool hasCompletedTutorialSequence(TutorialSequence tutorialSequence) =>
      enabledTutorialsInSequence(tutorialSequence).isEmpty;

  List<TutorialEnum> enabledTutorialsInSequence(
    TutorialSequence tutorialSequence,
  ) => tutorialSequence.where((t) => t.globallyEnabled).toList();

  /// Adds a single tutorial sequence to the end of the queue.
  void enqueueTutorialSequence(TutorialSequence tutorialSequence) {
    if (_sequence != null) {
      Logs().w(
        "Trying to enqueue tutorial sequence while previous sequence is still active",
      );
      return;
    }

    final enabledTutorials = enabledTutorialsInSequence(tutorialSequence);

    if (enabledTutorials.isEmpty) {
      Logs().i("All tutorials in sequence are disabled, skipping");
      return;
    }

    Logs().w("Enqueuing tutorial sequence with tutorials $enabledTutorials");

    _sequence = enabledTutorials;
    _index = 0;
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

    if (!isTutorialQueued(tutorial.tutorialType)) {
      Logs().w("Tutorial ${tutorial.tutorialType} is not next in queue");
      return;
    }

    if (activeTutorialNotifier.value != null) {
      Logs().w(
        "Tutorial ${activeTutorialNotifier.value?.tutorial.tutorialType} already open",
      );
    }

    final opened = _openTutorialOverlay(context);
    if (!opened) {
      Logs().e(
        "Failed to open tutorial overlay for tutorial ${tutorial.tutorialType}",
      );
      return;
    }

    activeTutorialNotifier.value = (
      tutorial: tutorial,
      stepIndex: initialStepIndex,
    );
    _index++;
  }

  bool _openTutorialOverlay(BuildContext context) {
    if (MatrixState.pAnyState.isOverlayOpen(overlayKey: _sequenceOverlayKey)) {
      Logs().w("Tutorial overlay is already open");
      return true;
    }

    // Open the persistent sequence overlay once for the entire sequence.
    // Subsequent tutorials in the sequence reuse this overlay so that the
    // blocking dark layer is never removed between steps.
    final entry = OverlayEntry(
      builder: (overlayContext) {
        return ValueListenableBuilder<
          ({TutorialModel tutorial, int stepIndex})?
        >(
          valueListenable: activeTutorialNotifier,
          builder: (context, value, _) {
            if (value == null) {
              // Between tutorials: block all interaction without showing UI.
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
              );
            }
            return TutorialOverlayWidget(
              key: ValueKey(value.tutorial.tutorialType),
              tutorial: value.tutorial,
              initialStepIndex: value.stepIndex,
            );
          },
        );
      },
    );

    return MatrixState.pAnyState.openOverlay(
      entry,
      context,
      rootOverlay: true,
      overlayKey: _sequenceOverlayKey,
      canPop: false,
      blockOverlay: true,
    );
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
  void requestGoBack({required TutorialModel currentTutorial}) {
    if (!hasPreviousTutorial(currentTutorial.tutorialType)) return;

    // Decrement by 2: undo the last launch increment, then step back one more
    // so that after the previous tutorial calls launchTutorial (which does
    // _index++) the index is back to _index - 1.
    _index -= 2;

    final previousTutorialEnum = _sequence![_index];

    // Hide the current tutorial content. The overlay itself stays open so the
    // user cannot tap the underlying UI while the previous tutorial re-prepares.
    activeTutorialNotifier.value = null;

    // Defer the stream emission to the next frame so that the closing widget's
    // dispose → onCloseTutorial runs before host widgets try to launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _backNavigationStream.add(previousTutorialEnum);
    });
  }

  void clearActiveTutorial(TutorialEnum tutorial) {
    if (!isTutorialActive(tutorial)) {
      Logs().w(
        "Trying to clear active tutorial $tutorial but it is not currently active",
      );
      return;
    }
    activeTutorialNotifier.value = null;
  }

  /// Cancels the active tutorial and the whole sequence, immediately closing
  /// the persistent overlay. Use this when a host widget is unexpectedly
  /// disposed while a tutorial is active (e.g., the user navigated away from
  /// the chat room), as opposed to [clearActiveTutorial] which is for natural
  /// step-by-step completion.
  void cancelTutorial() {
    Logs().w("Cancelling tutorial and clearing entire sequence");
    final tutorial = activeTutorialNotifier.value?.tutorial.tutorialType;
    _closeOverlay();
    reset();

    if (tutorial != null) {
      _closedTutorialStream.add(tutorial);
    }
  }

  void onCloseTutorial(TutorialEnum tutorial, {bool completed = false}) {
    if (_sequence == null) {
      Logs().w(
        "Received tutorial complete event for tutorial $tutorial but no active tutorial sequence",
      );
    } else if (_index >= _sequence!.length) {
      Logs().i("Reached end of tutorial sequence");
      _sequence = null;
      _index = 0;
      _closeOverlay();
    }

    // Only clear _activeTutorial if it still matches this tutorial — a
    // requestGoBack() may have already set it to a newly launched model.
    if (activeTutorialNotifier.value?.tutorial.tutorialType == tutorial) {
      activeTutorialNotifier.value = null;
    }

    // Only mark the tutorial fully seen when all steps were completed.
    // A mid-tutorial close preserves the saved step progress so the user
    // can resume from where they left off.
    if (completed) {
      tutorial.markSeen();
    }
    _closedTutorialStream.add(tutorial);
  }

  void _closeOverlay() {
    // Defer the actual overlay removal to avoid removing the overlay entry
    // while we are still in the middle of a widget rebuild/dispose.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MatrixState.pAnyState.closeOverlay(_sequenceOverlayKey);
    });
  }
}
