import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/main.dart' as app;
import 'package:fluffychat/features/notifications/enable_notifications_dialog.dart';
import 'package:fluffychat/features/notifications/suggest_mobile_dialog.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_course_details_subpage.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

import 'perf_harness.dart';
import 'perf_output_io.dart'
    if (dart.library.js_interop) 'perf_output_web.dart';

/// Performance benchmark: scrolling one course's plan, the full list of its
/// missions and activities. The tester names the course, so every run of a
/// comparison measures the same one. How to run it: [benchmark].
///
///   fvm flutter drive --profile --keep-app-running -d DEVICE_ID
///     --dart-define=PERF_COURSE='!spaceid:server'
///     --driver=test_driver/perf_driver.dart
///     --target=integration_test/perf/course_perf_test.dart
///
/// On web: web_runner.js --param 'course=!spaceid:server'.
void main() => benchmark(
  'course_scroll',
  warmupPasses: 1,
  body: (run) async {
    final tester = run.tester;
    const definedCourse = String.fromEnvironment('PERF_COURSE');
    final courseId = run.urlParameters['course'] ?? definedCourse;
    run.target = courseId;

    app.main();
    await waitFor(
      tester,
      () => isSignedIn(tester),
      timeout: const Duration(seconds: 60),
      failure: notSignedIn,
    );
    final client = tester.state<MatrixState>(find.byType(Matrix)).client;
    if (courseId.isEmpty) {
      // List the account's courses so the tester can choose one.
      for (final r in client.rooms.where(
        (r) => r.isSpace && r.membership == Membership.join,
      )) {
        perfOutput('PERF course: ${r.id}  ${r.getLocalizedDisplayname()}');
      }
      fail(
        'Name the course to scroll: --dart-define=PERF_COURSE=<space id>, or '
        'on web --param course=<space id>. Courses on this account are listed '
        'above.',
      );
    }
    // Signed in comes before the first sync has loaded the courses.
    await waitFor(
      tester,
      () {
        final room = client.getRoomById(courseId);
        return room != null &&
            room.isSpace &&
            room.membership == Membership.join;
      },
      timeout: const Duration(seconds: 30),
      failure: '$courseId is not a course this account has joined.',
    );
    perfOutput('PERF signed in');

    // The course plan's full list ("See all"): the part of the course page
    // with real length. The card itself shows short previews of each section.
    FluffyChatApp.router.go('/?c=$courseId&left=course:course/all');
    final view = find.byType(LeftPanelCourseDetailsSubpage);
    await waitFor(
      tester,
      () => view.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      failure: 'The course plan did not open.',
    );
    // Opening a course asks the learner to turn on notifications when they
    // are off, at most once per interval. Close it as a learner would,
    // without turning them on.
    await pause(tester, const Duration(seconds: 3));
    final prompt = find.byWidgetPredicate(
      (w) => w is EnableNotificationsDialog || w is SuggestMobileDialog,
    );
    if (prompt.evaluate().isNotEmpty) {
      await tester.tap(
        find.descendant(of: prompt, matching: find.byIcon(Icons.close)),
      );
      await pause(tester, const Duration(seconds: 1));
    }
    // On a phone the course opens as a sheet at its peek, which shows only
    // the progress bar. A tap on the sheet's handle opens it to full, as a
    // learner would. Wide layouts have no handle.
    final label = L10n.of(tester.element(view)).resizeCoursePanel;
    final handle = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == label,
    );
    if (handle.evaluate().isNotEmpty) {
      await tester.tap(handle);
      await pause(tester, const Duration(seconds: 1));
    }
    // The plan shows a spinner until its missions load, which on a phone
    // takes longer than on web.
    await waitFor(
      tester,
      () => find
          .descendant(of: view, matching: find.byType(ListView))
          .evaluate()
          .isNotEmpty,
      timeout: const Duration(seconds: 60),
      failure: 'The course plan did not load.',
    );
    // Let its images load before measuring.
    await pause(tester, const Duration(seconds: 8));

    final scrollable = mainScrollable(view, 'course plan');
    final list = findScrollable(scrollable);
    // The drags reach 800 px down; a shorter page would measure a list
    // hitting its end.
    final content = scrollable.position.maxScrollExtent;
    if (content < 1000) {
      fail(
        '$courseId has ${content.round()} px of course plan to scroll; the '
        'scenario needs at least 1,000. Choose a course with more activities.',
      );
    }
    perfOutput('PERF course plan open, ${content.round()} px to scroll');

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
          'scroll the course plan.',
        );
      }
      passes.add(summarize(timings, run.budgetMs));
      perfOutput('PERF pass ${pass + 1}: ${passes.last}');
      // Back to the top without a drag: on phones the course is a bottom sheet,
      // and a drag past its top would pull the sheet down instead.
      scrollable.position.jumpTo(0);
      await pause(tester, const Duration(seconds: 2));
    }
    return passes;
  },
);
