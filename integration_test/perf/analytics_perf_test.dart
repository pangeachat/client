import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/morph_analytics_list_view.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/vocab_analytics_list_view.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';

import 'perf_harness.dart';
import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// Each analytics panel: its route token and the widget that shows it.
const _panels = {
  'vocab': VocabAnalyticsListView,
  'grammar': MorphAnalyticsListView,
  'sessions': ActivityArchive,
};

/// Performance benchmark: scrolling one analytics panel. Each run measures
/// one panel, vocab unless another is named, and records which. How to run
/// it: [benchmark].
///
///   fvm flutter drive --profile --keep-app-running -d DEVICE_ID
///     [--dart-define=PERF_PANEL=vocab|grammar|sessions]
///     --driver=test_driver/perf_driver.dart
///     --target=integration_test/perf/analytics_perf_test.dart
///
/// On web: web_runner.js [--param panel=vocab|grammar|sessions].
void main() => benchmark(
  'analytics_scroll',
  warmupPasses: 1,
  body: (run) async {
    final tester = run.tester;
    const definedPanel = String.fromEnvironment(
      'PERF_PANEL',
      defaultValue: 'vocab',
    );
    final panel = run.urlParameters['panel'] ?? definedPanel;
    final panelType = _panels[panel];
    if (panelType == null) {
      fail('Unknown panel "$panel": use one of ${_panels.keys.join(', ')}.');
    }
    run.target = panel;

    app.main();
    await waitFor(
      tester,
      () => isSignedIn(tester),
      timeout: const Duration(seconds: 60),
      failure: notSignedIn,
    );
    perfOutput('PERF signed in');

    FluffyChatApp.router.go('/?right=analytics:$panel');
    final view = find.byType(panelType);
    await waitFor(
      tester,
      () => view.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      failure: 'The $panel panel did not open.',
    );
    // Let the analytics load and the list settle before measuring.
    await pause(tester, const Duration(seconds: 8));

    // The panel's main list: the vertical scroll view with the most content,
    // inside the panel or around it.
    final candidates =
        [
              ...find
                  .descendant(of: view, matching: find.byType(Scrollable))
                  .evaluate(),
              ...find
                  .ancestor(of: view, matching: find.byType(Scrollable))
                  .evaluate(),
            ]
            .map((e) => (e as StatefulElement).state as ScrollableState)
            .where((s) => s.position.axis == Axis.vertical);
    if (candidates.isEmpty) fail('The $panel panel has no vertical list.');
    final scrollable = candidates.reduce(
      (a, b) =>
          a.position.maxScrollExtent >= b.position.maxScrollExtent ? a : b,
    );
    final list = find.byWidget(scrollable.widget);
    // The drags reach 800 px down; a shorter panel would measure a list
    // hitting its end.
    final content = scrollable.position.maxScrollExtent;
    if (content < 1000) {
      fail(
        'The $panel panel has ${content.round()} px to scroll; the scenario '
        'needs at least 1,000, so this account needs more $panel history.',
      );
    }
    perfOutput('PERF $panel open, ${content.round()} px to scroll');

    final passes = <Map<String, Object?>>[];
    for (var pass = 0; pass < 5; pass++) {
      final recorder = FrameRecorder()..start();
      // Two drags down, then back and forth over the same stretch, so every
      // pass scrolls the same content.
      for (var i = 0; i < 16; i++) {
        final down = i < 2 || i.isOdd;
        await tester.timedDrag(
          list,
          Offset(0, down ? -400 : 400),
          const Duration(milliseconds: 200),
        );
        await pause(tester, const Duration(milliseconds: 150));
      }
      final timings = await recorder.stop(tester);
      if (timings.length < 30) {
        fail(
          'Pass ${pass + 1} drew ${timings.length} frames: the drags did not '
          'scroll the $panel panel.',
        );
      }
      passes.add(summarize(timings, run.budgetMs));
      perfOutput('PERF pass ${pass + 1}: ${passes.last}');
      // Back to the top, so the next pass starts where this one did.
      await tester.timedDrag(
        list,
        const Offset(0, 1000),
        const Duration(milliseconds: 300),
      );
      await pause(tester, const Duration(seconds: 2));
    }
    return passes;
  },
);
