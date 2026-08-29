import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_data_service.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_notifier.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The state bag for one standalone practice session. Owned by
/// [PracticeSessionHolder], NOT by the practice panel widget, so closing the
/// panel keeps the session alive and reopening resumes it. See
/// practice-exercises.instructions.md § Session Persistence & Lifecycle.
class PracticeSessionState {
  final ConstructTypeEnum type;
  final PracticeSessionController sessionController =
      PracticeSessionController();
  final AnalyticsPracticeDataService dataService =
      AnalyticsPracticeDataService();

  /// The exercise currently on screen. Every session-flow transition writes
  /// here (loading, loaded, error, and idle on completion), so it doubles as
  /// the rebuild backbone for both the panel and the cluster badge — including
  /// transitions that complete after the panel that started them was closed.
  final ExerciseNotifier practiceExerciseState = ExerciseNotifier(
    const AsyncState.idle(),
  );
  final AnalyticsPracticeNotifier notifier = AnalyticsPracticeNotifier();
  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  /// Wall-clock of the last time the learner touched this session — answering,
  /// skipping, taking a hint, or reopening the panel. Distinct from
  /// [AnalyticsPracticeSessionModel.startedAt], which never moves: this one is
  /// what the idle timeout measures, so a slow-but-active learner is never cut
  /// off. See practice-exercises.instructions.md § Session Persistence &
  /// Lifecycle.
  DateTime lastInteractionAt = DateTime.now();

  PracticeSessionState(this.type);

  /// Started, not completed, not errored — the session the cluster badge shows
  /// and the same-section analytics block keys off.
  bool get isLive {
    final session = sessionController.session;
    return session != null &&
        !session.isComplete &&
        sessionController.sessionError == null;
  }
}

/// Holds the one live standalone practice session (vocab OR grammar — one at a
/// time) so it survives practice-panel teardown. In-memory only by design: a
/// refresh or app restart starts fresh. Session state objects are dropped on
/// replace/end rather than disposed — a same-frame panel may still be
/// listening, and they hold no timers or streams, so GC is safe.
///
/// The holder also owns the **idle watchdog**: a live session left untouched
/// for [AnalyticsPracticeConstants.idleTimeout] is auto-ended, because a
/// learner who hasn't come back in half an hour isn't coming back, and the
/// wall-clock timer would otherwise run up an absurd elapsed time.
///
/// The watchdog [Timer] alone cannot enforce that: it does not run while the
/// app is backgrounded or the device is asleep. So the deadline is also
/// re-evaluated on wall-clock at the two moments the app can act on it —
/// returning to the foreground, and opening a practice panel.
class PracticeSessionHolder extends ChangeNotifier with WidgetsBindingObserver {
  PracticeSessionHolder._();
  static final PracticeSessionHolder instance = PracticeSessionHolder._();

  PracticeSessionState? _current;
  StreamSubscription<void>? _languageSubscription;

  /// One-shot idle watchdog, rescheduled on every interaction. Lives on the
  /// holder rather than [PracticeSessionState] so a dropped session never
  /// leaves a timer behind.
  Timer? _idleTimer;

  bool _timeoutNoticePending = false;

  bool _observingLifecycle = false;

  /// Count of attached practice panel widgets — a COUNT because on a panel
  /// swap (vocab → grammar) the new panel's initState runs before the old
  /// one's dispose. The panel handles language changes itself (restart in
  /// place); the holder only drops the session on language change when no
  /// panel is watching.
  int _attachedPanels = 0;

  void attachPanel() => _attachedPanels++;
  void detachPanel() => _attachedPanels--;

  PracticeSessionState? get current => _current;

  /// Set when a live session was dropped for idleness, cleared by whoever
  /// tells the learner. Only the timeout sets it — an explicit end or a
  /// replace is the learner's own doing and needs no notice.
  bool get hasTimeoutNotice => _timeoutNoticePending;

  bool consumeTimeoutNotice() {
    final pending = _timeoutNoticePending;
    _timeoutNoticePending = false;
    return pending;
  }

  ConstructTypeEnum? get liveType =>
      _current?.isLive == true ? _current!.type : null;

  bool get hasUnfinishedSession => liveType != null;

  /// Whether opening [type]'s analytics summary/details is blocked (no peeking
  /// at definitions mid-session) — callers resume practice instead.
  bool blocksAnalytics(ConstructTypeEnum type) => liveType == type;

  /// Return the held session for [type] (resume — completed sessions included,
  /// so reopening shows the completion view), or start holding a fresh one,
  /// replacing any other-type session. Confirmation for replacing an
  /// unfinished session happens at the tap site, before navigation.
  PracticeSessionState claim(ConstructTypeEnum type) {
    _ensureLanguageSubscription();
    _ensureLifecycleObserver();

    // Evaluate before resuming, not after: a session the learner comes back to
    // an hour later has already expired, and reopening the panel must not be
    // the interaction that rescues it. Timers are suspended while the app is
    // backgrounded, so this wall-clock check — not the watchdog — is what
    // catches the common "left the app, came back tomorrow" case.
    evaluateIdleTimeout();

    final current = _current;
    if (current != null && current.type == type) {
      markInteraction();
      return current;
    }

    _current = PracticeSessionState(type);
    _scheduleIdleTimeout();
    notifyListeners();
    return _current!;
  }

  /// Explicit end (the header's End control, or a confirmed replace): drop the
  /// session and clear the badge.
  void end() {
    if (_current == null) return;
    _current = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    notifyListeners();
  }

  /// Push the idle deadline out to [AnalyticsPracticeConstants.idleTimeout]
  /// from now. Called for every learner-driven session event.
  void markInteraction() {
    final current = _current;
    if (current == null) return;
    current.lastInteractionAt = DateTime.now();
    _scheduleIdleTimeout();
  }

  /// The timeout decision, made on wall-clock so it is correct whenever it
  /// runs: ends the held session if it is live and idle past the limit, and
  /// otherwise re-arms the watchdog.
  @visibleForTesting
  void evaluateIdleTimeout() {
    final current = _current;
    if (current == null) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }

    final idleFor = DateTime.now().difference(current.lastInteractionAt);
    if (idleFor < AnalyticsPracticeConstants.idleTimeout) {
      _scheduleIdleTimeout();
      return;
    }

    // Past the limit but not live — a completed session's review, or a load
    // that errored. Nothing to end; just stop watching.
    if (!current.isLive) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }

    _timeoutNoticePending = true;
    end();
  }

  void _scheduleIdleTimeout() {
    _idleTimer?.cancel();
    final current = _current;
    if (current == null) return;

    final remaining =
        AnalyticsPracticeConstants.idleTimeout -
        DateTime.now().difference(current.lastInteractionAt);
    _idleTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      evaluateIdleTimeout,
    );
  }

  /// Re-evaluate liveness after a session-flow transition the notifiers don't
  /// cover (session load finished/failed).
  void bump() => notifyListeners();

  /// A backgrounded app runs no watchdog, so coming back to the foreground is
  /// where a session that idled out while away is actually caught — otherwise
  /// it survives until the learner next opens the practice panel, badge
  /// counting up the whole time (#7812). This is also what re-arms the timer
  /// against real elapsed time after a suspend.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    evaluateIdleTimeout();
  }

  void _ensureLifecycleObserver() {
    if (_observingLifecycle) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    } catch (_) {
      // Unit tests exercise the holder without a binding. Nothing is lost but
      // the resume hook, and those tests drive [didChangeAppLifecycleState]
      // directly.
    }
  }

  void _ensureLanguageSubscription() {
    if (_languageSubscription != null) return;
    try {
      _languageSubscription = MatrixState
          .pangeaController
          .userController
          .languageStream
          .stream
          .listen((_) => _onLanguageUpdate());
    } catch (_) {
      // Unit tests exercise the holder without an initialized
      // PangeaController; the subscription is background-session cleanup only.
    }
  }

  void _onLanguageUpdate() {
    // An open panel restarts its session for the new language itself; only an
    // orphaned background session must be dropped (its targets are stale).
    if (_attachedPanels <= 0) end();
  }
}
