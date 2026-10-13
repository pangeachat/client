import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/routes/chat_list/chat_list_body.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';

import 'perf_harness.dart';
import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// Performance benchmark: chat list scrolling. How to run it: [benchmark].
///
///   fvm flutter drive --profile --keep-app-running -d DEVICE_ID
///     --driver=test_driver/perf_driver.dart
///     --target=integration_test/perf/chat_list_perf_test.dart
void main() => benchmark(
  'chat_list_scroll',
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

    FluffyChatApp.router.go('/?left=chats');
    final lists = find.descendant(
      of: find.byType(ChatListViewBody),
      matching: find.byType(Scrollable),
    );
    await waitFor(
      tester,
      () => lists.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      failure: 'The chat list did not open.',
    );
    final list = lists.first;
    perfOutput('PERF chat list open');
    // Let rows, avatars and the first sync settle before measuring.
    await pause(tester, const Duration(seconds: 5));

    // Five passes: compare.js drops the first (one-time costs) and needs the
    // rest to tell a real change from run-to-run spread.
    final passes = <Map<String, Object?>>[];
    for (var pass = 0; pass < 5; pass++) {
      final recorder = FrameRecorder()..start();
      // Net scroll never returns to the top, so on phones the drag stays in
      // the list instead of collapsing the bottom sheet it sits in. Fast,
      // long drags bring several new rows into view per frame, so a slower
      // row build shows up in the frame times instead of hiding in the
      // frames that only move rows already built.
      for (var i = 0; i < 16; i++) {
        final down = i < 2 || i.isOdd;
        await tester.timedDrag(
          list,
          Offset(0, down ? -800 : 800),
          const Duration(milliseconds: 200),
        );
        await pause(tester, const Duration(milliseconds: 150));
      }
      passes.add(summarize(await recorder.stop(tester), run.budgetMs));
      perfOutput('PERF pass ${pass + 1}: ${passes.last}');
      await pause(tester, const Duration(seconds: 2));
    }
    return passes;
  },
);
