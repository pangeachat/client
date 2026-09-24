import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/routes/chat_list/chat_list_body.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// Performance benchmark: chat list scrolling (testing.instructions.md §
/// Performance benchmark). It measures whichever account is signed in on the
/// device, so pass --keep-app-running: without it `flutter drive` uninstalls
/// the app when the run ends, and the sign-in goes with it. Sign in once in a
/// normal build (`fvm flutter run --profile`): the benchmark build ignores
/// real touches, so nobody can sign in inside it.
///
///   fvm flutter drive --profile --keep-app-running -d DEVICE_ID
///     --driver=test_driver/perf_driver.dart
///     --target=integration_test/perf/chat_list_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('chat list scroll', (tester) async {
    final testOnError = FlutterError.onError;
    // Read before the app starts: its router rewrites the URL and drops this.
    final urlRefreshRate = double.tryParse(
      Uri.base.queryParameters['refreshRate'] ?? '',
    );
    app.main();
    try {
      await _run(tester, binding, urlRefreshRate);
    } catch (e, s) {
      // The runner reports only "Instance of FlutterErrorDetails".
      perfOutput('PERF FAILED: $e\n$s');
      rethrow;
    } finally {
      // The app installs its own error sink at startup. Restoring the test's
      // before anything propagates is what lets a failure here fail the run;
      // left in place, the app's sink reports it and the run looks green.
      FlutterError.onError = testOnError;
    }
  });
}

Future<void> _run(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  double? urlRefreshRate,
) async {
  await _waitFor(
    tester,
    () =>
        find.byType(Matrix).evaluate().isNotEmpty &&
        tester.state<MatrixState>(find.byType(Matrix)).client.isLogged(),
    timeout: const Duration(seconds: 60),
    failure:
        'No account is signed in on this device. Sign in once in a profile '
        'build of the app, then run the benchmark again.',
  );
  perfOutput('PERF signed in');

  FluffyChatApp.router.go('/?left=chats');
  final lists = find.descendant(
    of: find.byType(ChatListViewBody),
    matching: find.byType(Scrollable),
  );
  await _waitFor(
    tester,
    () => lists.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 30),
    failure: 'The chat list did not open.',
  );
  final list = lists.first;
  perfOutput('PERF chat list open');
  // Let rows, avatars and the first sync settle before measuring.
  await _pause(tester, const Duration(seconds: 5));

  // Flutter web always reports 60 Hz, so web_runner.js measures the browser's
  // real frame rate and passes it in the URL. Phones report their own.
  final refreshRate = urlRefreshRate ?? tester.view.display.refreshRate;
  final budgetMs = 1000 / refreshRate;
  final passes = <Map<String, Object?>>[];
  // Five passes: compare.js drops the first (one-time costs) and needs the
  // rest to tell a real change from run-to-run spread.
  for (var pass = 0; pass < 5; pass++) {
    passes.add(
      await _measure(tester, budgetMs, () async {
        // Net scroll never returns to the top, so on phones the drag stays
        // in the list instead of collapsing the bottom sheet it sits in.
        // Fast, long drags bring several new rows into view per frame, so a
        // slower row build shows up in the frame times instead of hiding in
        // the frames that only move rows already built.
        for (var i = 0; i < 16; i++) {
          final down = i < 2 || i.isOdd;
          await tester.timedDrag(
            list,
            Offset(0, down ? -800 : 800),
            const Duration(milliseconds: 200),
          );
          await _pause(tester, const Duration(milliseconds: 150));
        }
      }),
    );
    perfOutput('PERF pass ${pass + 1}: ${passes.last}');
    await _pause(tester, const Duration(seconds: 2));
  }

  binding.reportData = {
    'scenario': 'chat_list_scroll',
    'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    'refreshRate': refreshRate,
    'budgetMs': budgetMs,
    'passes': passes,
  };
  // One JSON line: the web runner reads results from the console, since the
  // web build runs without flutter drive (see web_runner.js).
  perfOutput('PERF_RESULT ${jsonEncode(binding.reportData)}');
}

Future<void> _pause(WidgetTester tester, Duration duration) async {
  await Future<void>.delayed(duration);
  await tester.pump();
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String failure,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail(failure);
    await _pause(tester, const Duration(milliseconds: 250));
  }
}

/// Every frame drawn while [action] runs, as p50 / p90 / worst build and
/// raster times and the frames that missed the display's budget.
Future<Map<String, Object?>> _measure(
  WidgetTester tester,
  double budgetMs,
  Future<void> Function() action,
) async {
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> batch) => timings.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(collect);
  await action();
  // The engine reports timings in batches; wait for the last one.
  await _pause(tester, const Duration(seconds: 1));
  SchedulerBinding.instance.removeTimingsCallback(collect);

  final build = timings.map((t) => t.buildDuration.inMicroseconds / 1000);
  final raster = timings.map((t) => t.rasterDuration.inMicroseconds / 1000);
  return {
    'frames': timings.length,
    'buildMs': _percentiles(build.toList()),
    'rasterMs': _percentiles(raster.toList()),
    'missedBuildBudget': build.where((ms) => ms > budgetMs).length,
    'missedRasterBudget': raster.where((ms) => ms > budgetMs).length,
  };
}

Map<String, double> _percentiles(List<double> values) {
  if (values.isEmpty) return {};
  values.sort();
  double at(double p) =>
      values[(p * values.length).floor().clamp(0, values.length - 1)];
  return {'p50': at(0.5), 'p90': at(0.9), 'worst': values.last};
}
