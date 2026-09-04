import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/features/tutorials/tutorial_constants.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_state_machine.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_widget.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/features/tutorials/tutorial_state_transition_events.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// How a host can put a tutorial on screen.
///
/// A tutorial's steps point at widgets, and the widget that owns them is the
/// only thing that can build the step data — so it registers as [owner]. When
/// that widget is not mounted, an ancestor that can *cause* it to mount (the
/// chat opening its toolbar) registers as [opener] instead. The owner always
/// wins; the opener runs only in its absence, and mounting the owner re-asks.
enum TutorialLaunchRole { owner, opener }

/// Prepares whatever UI state the tutorial needs and calls
/// [TutorialOverlayController.launchTutorial]. Preparation belongs here, in the
/// host that owns the target, and never in a switch over tutorial types
/// somewhere up the tree.
typedef TutorialLauncher = Future<void> Function();

/// App-scoped. One controller runs at most one sequence at a time, because the
/// tutorial overlay is a single blocking entry and the overlay registry refuses
/// to open anything while a blocking entry is up — two controllers would
/// contend for the same key and the loser would silently fail to launch.
///
/// A sequence outliving the screen it started on is the point: an orientation
/// tutorial spans the map and an activity, and the app tour spans panels.
class TutorialOverlayController {
  TutorialOverlayController({
    TutorialProgressSource progress = const TutorialProgressSource(),
  }) : _progress = progress;

  final TutorialProgressSource _progress;

  /// A machine over an empty sequence stands in while nothing is running, so
  /// every read (`tutorialType`, `hasCompletedSequence`, …) answers safely
  /// without callers null-checking.
  TutorialOverlayStateMachine _state = TutorialOverlayStateMachine(const []);

  /// The sequence as requested, before the seen/enabled filter. Kept for
  /// identity so a host can release the sequence it asked for.
  TutorialSequence? _activeSequence;

  final List<TutorialSequence> _queue = [];

  final Map<TutorialEnum, Map<TutorialLaunchRole, TutorialLauncher>>
  _launchers = {};

  /// True while a launcher is preparing UI state. Guards against a host that
  /// mounts *because* of that preparation immediately launching underneath it.
  bool _launchInFlight = false;

  /// What the current step is waiting for the learner to do, if it is an armed
  /// step. Held here rather than on the overlay because an armed step outlives
  /// the overlay by design: the learner walks off to do the thing, the scrim
  /// gets out of their way, and the tutorial resumes when they have done it —
  /// even in a later app session, since the resume step is persisted.
  TutorialStepArming? _armed;
  VoidCallback? _armedListener;

  TutorialOverlayStateMachine get state => _state;

  bool isTutorialQueued(TutorialEnum tutorial) =>
      _state.tutorialType == tutorial;

  bool get hasActiveSequence => _activeSequence != null;

  /// Whether this learner still has [tutorial] coming — unseen, and not yet
  /// walked to its end. Asked by a host whose trigger belongs to one specific
  /// tutorial, so the trigger stays silent once that tutorial is done.
  ///
  /// **A caller must never cache a `false` from this.** The answer lives on the
  /// learner's profile, which loads asynchronously and reports everything as
  /// *already seen* until it does — and which the learner can reset from
  /// settings. A remembered "nothing left to show" outlives the profile it came
  /// from, and on a host that is never remounted (the world map) that retires
  /// the tutorial for the rest of the session. Ask again; the answer is a map
  /// lookup. See tutorials.instructions.md on trigger evaluation.
  bool isPending(TutorialEnum tutorial) => _progress.isEnabled(tutorial);

  /// Puts the current step back on screen when a sequence is running but nothing
  /// is showing it. Two ways that happens: the host that owned the step was torn
  /// down, or the overlay was force-closed from elsewhere (closing a chat clears
  /// every overlay), which leaves the machine believing a tutorial is up.
  ///
  /// Callers check their own surface is present FIRST — resuming onto a surface
  /// that isn't there relaunches a step that immediately dismisses itself again.
  void resumeIfStranded() {
    // An armed step is deliberately left off screen: withdrawing the overlay so
    // the learner can act IS the step. It resumes when they act.
    if (_activeSequence == null || _armed != null) return;

    final overlayOpen = MatrixState.pAnyState.isOverlayOpen(
      overlayKey: TutorialConstants.sequenceOverlayKey,
    );
    if (_state.model.activeTutorial != null && overlayOpen) return;

    // Clear the stale "a tutorial is showing" belief first, or launchTutorial's
    // own guard refuses the relaunch and the sequence stays stuck.
    if (_state.model.activeTutorial != null) {
      _state.dispatch(ResetTutorialEvent());
    }
    _launchCurrent();
  }

  /// Runs [sequence] now if nothing else is running, else queues it. Returns
  /// whether it started. Dropping it instead would silently lose a tutorial
  /// whose trigger fired while another sequence held the overlay.
  bool requestSequence(TutorialSequence sequence) {
    if (_isSameSequence(_activeSequence, sequence)) return false;

    if (_activeSequence != null) {
      if (!_queue.any((queued) => _isSameSequence(queued, sequence))) {
        _queue.add(sequence);
      }
      Logs().v("Tutorial sequence $sequence queued behind $_activeSequence");
      return false;
    }

    final enabled = sequence.where(_progress.isEnabled).toList();
    if (enabled.isEmpty) {
      Logs().v("Tutorial sequence $sequence has nothing left to show");
      return false;
    }

    _activeSequence = sequence;
    _state = TutorialOverlayStateMachine(
      enabled,
      initialStepIndex: _progress.resumeStep(enabled.first),
    );
    _launchCurrent();
    return true;
  }

  /// Gives up [sequence] — its host is going away, so nothing can put its
  /// remaining steps on screen. Progress is already persisted, so the next
  /// request resumes where it left off. Draining here is what keeps a queued
  /// sequence from being stranded behind an abandoned one.
  void releaseSequence(TutorialSequence sequence) {
    if (!_isSameSequence(_activeSequence, sequence)) {
      _queue.removeWhere((queued) => _isSameSequence(queued, sequence));
      return;
    }
    _endSequence();
  }

  void registerLauncher(
    TutorialEnum tutorial,
    TutorialLauncher launcher, {
    TutorialLaunchRole role = TutorialLaunchRole.owner,
  }) {
    (_launchers[tutorial] ??= {})[role] = launcher;

    // A host that mounts while its tutorial is the one waiting to go on screen
    // is itself the launch trigger — post-frame, since registration typically
    // happens during initState. Suppressed mid-launch: an opener that is still
    // preparing will re-ask once it finishes.
    if (isTutorialQueued(tutorial) &&
        _state.model.activeTutorial == null &&
        !_launchInFlight) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _launchCurrent());
      // A post-frame callback only runs if a frame is coming. Registration
      // usually rides one (the host just mounted), but not always — asking for
      // one is what stops the launch from sitting pending indefinitely.
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  /// Removes [launcher] only if it is the one currently registered.
  ///
  /// The identity check matters for a tutorial more than one host can own — the
  /// greeting fires on the world map or a course plan, whichever the learner
  /// reaches first. Without it, the second host to register and then leave would
  /// take the first host's registration with it, and nothing could launch the
  /// greeting again.
  void unregisterLauncher(
    TutorialEnum tutorial,
    TutorialLauncher launcher, {
    TutorialLaunchRole role = TutorialLaunchRole.owner,
  }) {
    final roles = _launchers[tutorial];
    if (roles == null || roles[role] != launcher) return;
    roles.remove(role);
    if (roles.isEmpty) _launchers.remove(tutorial);
  }

  bool _isSameSequence(TutorialSequence? a, TutorialSequence? b) {
    if (a == null || b == null) return false;
    return listEquals(a, b);
  }

  /// Starts watching for what the current step is waiting for, if anything.
  /// Called on every launch and every advance, so exactly one step is ever
  /// armed.
  void _syncArming() {
    _disarm();

    final tutorial = _state.model.activeTutorial;
    if (tutorial == null) return;
    final arming = tutorial.dataAt(_state.model.stepIndex).arming;
    if (arming == null) return;

    // Already done before the step was even shown (the learner was quicker than
    // the tutorial, or it resumed after the fact) — don't make them do it twice.
    if (arming.isSatisfied()) {
      forwardTutorial();
      return;
    }

    _armed = arming;
    _armedListener = () {
      if (_armed != arming) return;
      if (!arming.isSatisfied()) return;
      forwardTutorial();
    };
    arming.signal.addListener(_armedListener!);
  }

  void _disarm() {
    final listener = _armedListener;
    if (listener != null) _armed?.signal.removeListener(listener);
    _armed = null;
    _armedListener = null;
  }

  /// Asks whoever can show the queued tutorial to show it. Nothing happens if
  /// no host is registered — the tutorial stays queued and launches when one
  /// registers.
  Future<void> _launchCurrent() async {
    final tutorial = _state.tutorialType;
    if (tutorial == null || _launchInFlight) return;

    final owner = _launchers[tutorial]?[TutorialLaunchRole.owner];
    final launcher = owner ?? _launchers[tutorial]?[TutorialLaunchRole.opener];
    if (launcher == null) {
      Logs().v("No host registered to launch tutorial $tutorial");
      return;
    }

    _launchInFlight = true;
    try {
      await launcher();
    } finally {
      _launchInFlight = false;
    }

    // An opener's whole job is to make the owner mount. If one appeared and
    // nothing is on screen yet, ask it now.
    final ownerAppeared =
        owner == null &&
        _launchers[tutorial]?[TutorialLaunchRole.owner] != null;
    if (ownerAppeared &&
        _state.tutorialType == tutorial &&
        _state.model.activeTutorial == null) {
      await _launchCurrent();
    }
  }

  bool _hasModalAbove(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = ModalRoute.of(context);

    if (route == null) return false;
    return !route.isCurrent || navigator.canPop();
  }

  void launchTutorial({
    required BuildContext context,
    required TutorialModel tutorial,
    required bool isFocused,
  }) {
    // Checked first, and returns WITHOUT closing: a duplicate launch request —
    // the input bar taking focus while the sequence is already advancing to the
    // writing step — must never tear down the tutorial that is on screen. The
    // closes below are stale-overlay cleanup, and are only reached when nothing
    // is running.
    if (_state.model.activeTutorial != null) {
      Logs().w(
        "Another tutorial is already active: ${_state.model.activeTutorial!.tutorialType}",
      );
      return;
    }

    if (!isFocused) {
      Logs().w("Tutorial ${tutorial.tutorialType} is not locally enabled");
      _closeOverlay();
      return;
    }

    if (!isTutorialQueued(tutorial.tutorialType)) {
      Logs().w(
        "Tutorial ${tutorial.tutorialType} is not queued to launch next",
      );
      _closeOverlay();
      return;
    }

    if (_hasModalAbove(context)) {
      Logs().w(
        "Tutorial ${tutorial.tutorialType} blocked because another route/dialog is on top.",
      );
      _closeOverlay();
      return;
    }

    final opened = _openTutorialOverlay(context);
    if (!opened) {
      _closeOverlay();
      return;
    }

    _state.dispatch(LaunchTutorialEvent(tutorial));
    _syncArming();
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
        final machine = _state;
        return ListenableBuilder(
          listenable: machine,
          builder: (context, _) => TutorialOverlayWidget(
            model: machine.model,
            forward: forwardTutorial,
            back: backTutorial,
            reset: resetTutorial,
            decline: declineCurrentTutorial,
            setTutorialTransitioning: setTutorialTransitioning,
            enabledForward: machine.canGoForward,
            enabledBack: machine.canGoBack,
            completedSteps:
                machine.completedStepsOffset + machine.model.stepIndex + 1,
            totalSteps: machine.totalStepsInSequence,
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
    if (previousType == null) return;

    previousType.saveProgress(previousStepIndex + 1);
    GoogleAnalytics.completeTutorialStep(previousType.name, previousStepIndex);

    _state.dispatch(ForwardTutorialEvent());
    // Whatever the previous step was waiting for, it is done waiting.
    _disarm();

    if (!couldGoForward) {
      _endSequence();
      return;
    }

    // "Is anything on screen?", not "did the tutorial change?". Crossing into
    // the next tutorial clears the active tutorial, and so does an armed step
    // whose overlay got out of the learner's way — both need a host to put the
    // new step up. A plain tap-advance within a tutorial keeps its overlay, and
    // only needs the new step armed.
    if (_state.model.activeTutorial == null) {
      _launchCurrent();
    } else {
      _syncArming();
    }
  }

  /// The learner declined this tutorial at a branch step: mark it seen, because
  /// they were asked and said no, and end the sequence rather than carrying on
  /// into steps they just opted out of.
  void declineCurrentTutorial() {
    final tutorial = _state.tutorialType;
    if (tutorial == null) return;
    GoogleAnalytics.declineTutorial(tutorial.name, _state.model.stepIndex);
    tutorial.saveProgress(tutorial.stepCount);
    _endSequence();
  }

  /// Re-opens the previous tutorial in the sequence at its last step.
  void backTutorial() {
    if (!_state.canGoBack) {
      _endSequence();
      return;
    }

    _state.dispatch(BackTutorialEvent());
    _disarm();

    if (_state.model.activeTutorial == null) {
      _launchCurrent();
    } else {
      _syncArming();
    }
  }

  /// The current tutorial leaves the screen without being completed — its
  /// target went away, or the learner navigated off. The sequence stays active
  /// so a re-mounting host resumes it; only [_endSequence] gives it up.
  ///
  /// Deliberately does NOT disarm: an armed step dismissing the overlay is the
  /// learner going off to do what it asked, which is exactly when the watch
  /// still has to be running.
  void resetTutorial() {
    _state.dispatch(ResetTutorialEvent());
    _closeOverlay();
  }

  void _endSequence() {
    _disarm();
    _state.dispatch(ResetTutorialEvent());
    _closeOverlay();
    // Not disposed: the overlay entry is still listening to it until the
    // post-frame close above runs. It holds no resources beyond listeners, so
    // dropping the reference is enough.
    _state = TutorialOverlayStateMachine(const []);
    _activeSequence = null;

    if (_queue.isEmpty) return;
    // Post-frame, so it runs AFTER the close above: [_closeOverlay] defers
    // removal to a post-frame callback, and they run in registration order.
    // Draining synchronously here let the next sequence find the still-present
    // entry, "reuse" it, insert nothing, and then have it removed underneath —
    // leaving the machine certain a tutorial was showing while nothing was.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainQueue());
  }

  void _drainQueue() {
    while (_queue.isNotEmpty) {
      if (requestSequence(_queue.removeAt(0))) return;
    }
  }

  void _closeOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MatrixState.pAnyState.closeOverlay(TutorialConstants.sequenceOverlayKey);
    });
    // A post-frame callback only runs if a frame is coming, and a close is often
    // the last thing to happen — without asking for one, the entry can sit on
    // screen (and anything queued behind it stays queued).
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}
