import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/routes/chat/activity_sessions/activity_stats_menu.dart';
import 'package:fluffychat/widgets/matrix.dart';

import 'chat_scroll.dart';
import 'perf_harness.dart';
import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// Performance benchmark: scrolling a running activity session's
/// conversation under its goal header. The tester names a session that has
/// started, where the account holds a role it has not finished, so every run
/// of a comparison measures the same one. How to run it: [benchmark].
///
///   fvm flutter drive --profile --keep-app-running -d DEVICE_ID
///     --dart-define=PERF_SESSION='!roomid:server'
///     --driver=test_driver/perf_driver.dart
///     --target=integration_test/perf/activity_session_perf_test.dart
///
/// On web: web_runner.js --param 'session=!roomid:server'.
void main() => benchmark(
  'activity_session_scroll',
  warmupPasses: 1,
  body: (run) async {
    final tester = run.tester;
    const definedSession = String.fromEnvironment('PERF_SESSION');
    final sessionId = run.urlParameters['session'] ?? definedSession;
    run.target = sessionId;

    app.main();
    await waitFor(
      tester,
      () => isSignedIn(tester),
      timeout: const Duration(seconds: 60),
      failure: notSignedIn,
    );
    final client = tester.state<MatrixState>(find.byType(Matrix)).client;
    // Why [r] is not a session this scenario can scroll, or null if it is.
    String? unusable(Room? r) {
      if (r == null) return 'not found';
      if (r.membership != Membership.join) return 'not joined';
      if (!r.isActivitySession) return 'not an activity session';
      // Before every role is filled, a session shows its start page instead
      // of the chat.
      if (!r.isActivityStarted) return 'not started';
      if (!r.isActiveInActivity) return 'no unfinished role for this account';
      return null;
    }

    if (sessionId.isEmpty) {
      // Signed in comes before the first sync has loaded the rooms.
      await pause(tester, const Duration(seconds: 10));
      // List the account's running sessions so the tester can choose one.
      for (final r in client.rooms.where((r) => unusable(r) == null)) {
        perfOutput('PERF session: ${r.id}  ${r.getLocalizedDisplayname()}');
      }
      fail(
        'Name the running session to scroll: --dart-define=PERF_SESSION=<room '
        'id>, or on web --param session=<room id>. Running sessions on this '
        'account are listed above.',
      );
    }
    // Signed in comes before the first sync has loaded the rooms.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    String? why;
    while ((why = unusable(client.getRoomById(sessionId))) != null) {
      if (DateTime.now().isAfter(deadline)) fail('$sessionId: $why.');
      await pause(tester, const Duration(milliseconds: 250));
    }
    perfOutput('PERF signed in');

    // Sessions are short (most on the test account hold under 800 px), so
    // the drags reach 600 px, not the chat scenario's 800.
    final list = await openChat(run, sessionId, minHistory: 700);
    if (find.byType(ActivityStatsMenu).evaluate().isEmpty) {
      fail('The session opened without its goal header.');
    }
    // A running session can receive messages, from the bot or another
    // learner. One arriving mid-run changes what the passes scroll, so the
    // run would not be comparable.
    final room = client.getRoomById(sessionId)!;
    final lastEvent = room.lastEvent?.eventId;
    final passes = await measureChatScroll(run, list, drag: 300);
    if (room.lastEvent?.eventId != lastEvent) {
      fail('A message arrived in the session during the run; run it again.');
    }
    return passes;
  },
);
