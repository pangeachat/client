import 'dart:ui';

import 'package:flutter/scheduler.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/routes/world/world_map.dart';

import 'perf_harness.dart';
import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// Performance benchmark: the first 15 seconds after the app starts, as a
/// returning user who is already signed in. One launch per run. How to run
/// it: [benchmark].
///
///   fvm flutter drive --profile --keep-app-running -d DEVICE_ID
///     --driver=test_driver/perf_driver.dart
///     --target=integration_test/perf/launch_perf_test.dart
void main() => benchmark(
  'launch',
  warmupPasses: 0,
  body: (run) async {
    final tester = run.tester;
    // Record from before the app starts, so the load window is complete.
    final recorder = FrameRecorder()..start();

    // The first screen is the first frame after which the home screen (the
    // world map) exists; frames before it only show loading. This callback
    // runs after each frame's build, and the engine's frame number is what
    // matches the frame to its timing below.
    int? firstScreenFrame;
    var watching = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (!watching || firstScreenFrame != null) return;
      if (find.byType(WorldMap).evaluate().isNotEmpty) {
        firstScreenFrame = PlatformDispatcher.instance.frameData.frameNumber;
      }
    });

    app.main();
    await Future<void>.delayed(const Duration(seconds: 15));
    watching = false;
    final timings = await recorder.stop(tester);

    if (!isSignedIn(tester)) fail(notSignedIn);
    if (firstScreenFrame == null) {
      fail('The app did not build its first screen within 15 s.');
    }
    final first = timings.where((t) => t.frameNumber == firstScreenFrame);
    if (first.length != 1) {
      fail('No frame timing carries the first screen\'s frame number.');
    }
    perfOutput(
      'PERF first screen: frame ${timings.indexOf(first.single) + 1} of '
      '${timings.length}',
    );

    return [
      {
        ...summarize(timings, run.budgetMs),
        'firstFrameBuildMs': buildMs(first.single),
        'firstFrameRasterMs': rasterMs(first.single),
        'totalBuildMs': timings.fold<double>(0, (sum, t) => sum + buildMs(t)),
      },
    ];
  },
);
