import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
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
class PracticeSessionHolder extends ChangeNotifier {
  PracticeSessionHolder._();
  static final PracticeSessionHolder instance = PracticeSessionHolder._();

  PracticeSessionState? _current;
  StreamSubscription<void>? _languageSubscription;

  /// Count of attached practice panel widgets — a COUNT because on a panel
  /// swap (vocab → grammar) the new panel's initState runs before the old
  /// one's dispose. The panel handles language changes itself (restart in
  /// place); the holder only drops the session on language change when no
  /// panel is watching.
  int _attachedPanels = 0;

  void attachPanel() => _attachedPanels++;
  void detachPanel() => _attachedPanels--;

  PracticeSessionState? get current => _current;

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

    final current = _current;
    if (current != null && current.type == type) return current;

    _current = PracticeSessionState(type);
    notifyListeners();
    return _current!;
  }

  /// Explicit end (the header's End control, or a confirmed replace): drop the
  /// session and clear the badge.
  void end() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// Re-evaluate liveness after a session-flow transition the notifiers don't
  /// cover (session load finished/failed).
  void bump() => notifyListeners();

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
