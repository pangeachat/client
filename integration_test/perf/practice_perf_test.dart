import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_choices_widget.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

import 'perf_harness.dart';
import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// Performance benchmark: opening a grammar practice session up to its first
/// exercise, without answering. Answering records XP on the account and
/// changes what later sessions pick, so a pass ends the session instead,
/// which writes nothing. Grammar, not vocab: a vocab exercise speaks its
/// prompt word, and its audio exercise can post audio into a chat. How to run
/// it: [benchmark].
///
///   fvm flutter drive --profile --keep-app-running -d DEVICE_ID
///     --driver=test_driver/perf_driver.dart
///     --target=integration_test/perf/practice_perf_test.dart
void main() => benchmark(
  'practice_open',
  warmupPasses: 1,
  body: (run) async {
    final tester = run.tester;
    app.main();
    await waitFor(
      tester,
      () => isSignedIn(tester),
      timeout: const Duration(seconds: 60),
      failure: notSignedIn,
    );
    perfOutput('PERF signed in');
    // Practice picks its exercises from the analytics store, so it opens only
    // once the store is ready, as it is by the time a learner reaches it.
    final analytics = tester
        .state<MatrixState>(find.byType(Matrix))
        .analyticsDataService;
    await waitFor(
      tester,
      () => !analytics.isInitializing,
      timeout: const Duration(seconds: 60),
      failure: 'The analytics store did not finish initializing.',
    );
    // A session left from an earlier run would open where it stopped.
    PracticeSessionHolder.instance.end();
    await pause(tester, const Duration(seconds: 5));

    final choices = find.byType(AnalyticsPracticeExerciseChoices);
    final passes = <Map<String, Object?>>[];
    for (var pass = 0; pass < 5; pass++) {
      final recorder = FrameRecorder()..start();
      await recorder.action('open practice', () async {
        FluffyChatApp.router.go('/?right=practice:grammar');
        await waitFor(
          tester,
          () => choices.evaluate().isNotEmpty,
          timeout: const Duration(seconds: 30),
          failure:
              'Grammar practice showed no exercise. Is this account '
              'subscribed, with enough grammar history to practice?',
        );
        // The first exercise's entrance, and the rest generating behind it.
        await pause(tester, const Duration(seconds: 3));
      });
      final timings = await recorder.stop(tester);
      passes.add(summarize(timings, run.budgetMs, actions: recorder.actions));
      perfOutput('PERF pass ${pass + 1}: ${passes.last}');
      // Close the panel and drop the session, so the next pass opens a new
      // one, the way the learner's End control does.
      FluffyChatApp.router.go('/');
      await pause(tester, const Duration(seconds: 1));
      PracticeSessionHolder.instance.end();
      await pause(tester, const Duration(seconds: 3));
    }
    return passes;
  },
);
