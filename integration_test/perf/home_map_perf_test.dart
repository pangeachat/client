import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/widgets/fluffy_chat_app.dart';

import 'perf_harness.dart';
import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// Performance benchmark: panning the home map. How to run it: [benchmark].
///
///   fvm flutter drive --profile --keep-app-running -d DEVICE_ID
///     --driver=test_driver/perf_driver.dart
///     --target=integration_test/perf/home_map_perf_test.dart
void main() => benchmark(
  'home_map_pan',
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

    FluffyChatApp.router.go('/');
    final map = find.byType(FlutterMap);
    await waitFor(
      tester,
      () => map.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      failure: 'The home map did not open.',
    );
    perfOutput('PERF map open');
    // Let the first tiles and pins load before measuring.
    await pause(tester, const Duration(seconds: 8));

    // Square loops (right, down, left, up) keep returning the camera to the
    // same area, so after the first pass (warm-up) its tiles are cached and
    // later passes measure drawing, not tile downloads.
    const loop = [
      Offset(-300, 0),
      Offset(0, -300),
      Offset(300, 0),
      Offset(0, 300),
    ];
    final passes = <Map<String, Object?>>[];
    for (var pass = 0; pass < 5; pass++) {
      final recorder = FrameRecorder()..start();
      for (var i = 0; i < 16; i++) {
        await tester.timedDrag(
          map.first,
          loop[i % loop.length],
          const Duration(milliseconds: 300),
        );
        await pause(tester, const Duration(milliseconds: 150));
      }
      final timings = await recorder.stop(tester);
      // A drag that landed on a card or control instead of the map draws
      // almost nothing; that is not a measurement of panning.
      if (timings.length < 30) {
        fail(
          'Pass ${pass + 1} drew ${timings.length} frames: the drags did not pan the map.',
        );
      }
      passes.add(summarize(timings, run.budgetMs));
      perfOutput('PERF pass ${pass + 1}: ${passes.last}');
      await pause(tester, const Duration(seconds: 2));
    }
    return passes;
  },
);
