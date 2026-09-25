import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fluffychat/widgets/matrix.dart';

import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// What every benchmark scenario receives (testing.instructions.md §
/// Performance benchmark).
class PerfRun {
  final WidgetTester tester;

  /// The display's frame budget: a frame that takes longer missed it.
  final double budgetMs;

  /// The page's URL parameters, read before the app started (its router
  /// rewrites the URL). On web this is how a scenario receives its inputs.
  final Map<String, String> urlParameters;

  /// What the scenario measured when that varies by run, such as which chat.
  /// compare.js refuses to compare results with different targets.
  String? target;

  PerfRun(this.tester, this.budgetMs, this.urlParameters);
}

/// Runs one benchmark scenario and reports its result.
///
/// [body] starts the app itself, so a scenario can start recording before
/// the first frame, and returns the passes it measured. The first
/// [warmupPasses] of them carry one-time costs, and compare.js leaves them out.
///
/// It measures whichever account is signed in on the device, so run it with
/// `flutter drive --keep-app-running` (test_driver/perf_driver.dart): without
/// it the app is uninstalled when the run ends, and the sign-in goes with it.
/// Sign in once in a normal build (`fvm flutter run --profile`), because the
/// benchmark build ignores real touches. On web use web_runner.js.
void benchmark(
  String scenario, {
  required int warmupPasses,
  required Future<List<Map<String, Object?>>> Function(PerfRun run) body,
}) {
  final binding = _AppFramesOnlyBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(scenario, (tester) async {
    final testOnError = FlutterError.onError;
    // Flutter web always reports 60 Hz, so web_runner.js measures the
    // browser's real frame rate and passes it in the URL. Read it before the
    // app starts: its router rewrites the URL and drops it. Phones report
    // their own.
    final urlParameters = Map.of(Uri.base.queryParameters);
    final refreshRate =
        double.tryParse(urlParameters['refreshRate'] ?? '') ??
        tester.view.display.refreshRate;
    final budgetMs = 1000 / refreshRate;
    try {
      final run = PerfRun(tester, budgetMs, urlParameters);
      final passes = await body(run);
      binding.reportData = {
        'scenario': scenario,
        if (run.target != null) 'target': run.target,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'refreshRate': refreshRate,
        'budgetMs': budgetMs,
        'warmupPasses': warmupPasses,
        'passes': passes,
      };
      // One JSON line: web_runner.js reads results from the console, since
      // the web build runs without flutter drive.
      perfOutput('PERF_RESULT ${jsonEncode(binding.reportData)}');
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

/// A live test binding that draws only the frames the app asks for.
///
/// Flutter's live test binding requests another frame after every frame it
/// draws, so under it an idle app still draws at the display's full rate,
/// redrawing the whole scene each time. Those frames are the test's, not the
/// app's: they would swamp a mostly idle window such as launch and add to
/// every pause between drags. A frame the app, an animation or a pump asked
/// for sets [hasScheduledFrame]; the binding's own follow-up request does not.
class _AppFramesOnlyBinding extends IntegrationTestWidgetsFlutterBinding {
  var _skipping = false;

  static var _created = false;

  /// Must run before anything else creates a binding, which [benchmark]
  /// does by calling it first.
  static IntegrationTestWidgetsFlutterBinding ensureInitialized() {
    if (!_created) {
      _created = true;
      _AppFramesOnlyBinding();
    }
    return IntegrationTestWidgetsFlutterBinding.instance;
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    // A null time stamp is the warm-up frame, which always draws.
    if (rawTimeStamp != null && !hasScheduledFrame) {
      _skipping = true;
      return;
    }
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  void handleDrawFrame() {
    if (_skipping) {
      _skipping = false;
      return;
    }
    super.handleDrawFrame();
  }
}

const notSignedIn =
    'No account is signed in on this device. Sign in once in a profile build '
    'of the app, then run the benchmark again.';

bool isSignedIn(WidgetTester tester) =>
    find.byType(Matrix).evaluate().isNotEmpty &&
    tester.state<MatrixState>(find.byType(Matrix)).client.isLogged();

Future<void> pause(WidgetTester tester, Duration duration) async {
  await Future<void>.delayed(duration);
  await tester.pump();
}

Future<void> waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String failure,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail(failure);
    await pause(tester, const Duration(milliseconds: 250));
  }
}

/// Collects every frame's timing between [start] and [stop].
class FrameRecorder {
  final _timings = <FrameTiming>[];

  void _collect(List<FrameTiming> batch) => _timings.addAll(batch);

  void start() => SchedulerBinding.instance.addTimingsCallback(_collect);

  Future<List<FrameTiming>> stop(WidgetTester tester) async {
    // The engine reports timings in batches; wait for the last one.
    await pause(tester, const Duration(seconds: 1));
    SchedulerBinding.instance.removeTimingsCallback(_collect);
    return List.of(_timings);
  }
}

double buildMs(FrameTiming t) => t.buildDuration.inMicroseconds / 1000;
double rasterMs(FrameTiming t) => t.rasterDuration.inMicroseconds / 1000;

/// p50 / p90 / worst build and raster times, and the frames that missed the
/// display's budget.
Map<String, Object?> summarize(List<FrameTiming> timings, double budgetMs) {
  final build = timings.map(buildMs).toList();
  final raster = timings.map(rasterMs).toList();
  return {
    'frames': timings.length,
    'buildMs': _percentiles(build),
    'rasterMs': _percentiles(raster),
    'missedBuildBudget': build.where((ms) => ms > budgetMs).length,
    'missedRasterBudget': raster.where((ms) => ms > budgetMs).length,
  };
}

Map<String, double> _percentiles(List<double> values) {
  if (values.isEmpty) return {};
  final sorted = [...values]..sort();
  double at(double p) =>
      sorted[(p * sorted.length).floor().clamp(0, sorted.length - 1)];
  return {'p50': at(0.5), 'p90': at(0.9), 'worst': sorted.last};
}
