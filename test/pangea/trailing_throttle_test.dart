import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/utils/trailing_throttle.dart';

/// #8735 — the discovery throttle must trail, not drop. The sync tick a
/// coursemate's session-filled event produces is often the LAST trigger of a
/// burst (it lands right after the message that opened the window), and a
/// dropping throttle threw exactly that one away.
void main() {
  const window = Duration(seconds: 3);

  testWidgets(
    'a burst inside one window runs once now and once when the window ends',
    (tester) async {
      final throttle = TrailingThrottle(window);
      var runs = 0;
      Future<void> action() async => runs++;

      unawaited(throttle.run(action));
      unawaited(throttle.run(action));
      unawaited(throttle.run(action));
      await tester.pump();
      expect(runs, 1);

      await tester.pump(window - const Duration(milliseconds: 1));
      expect(runs, 1, reason: 'the follow-up waits for the window to close');
      await tester.pump(const Duration(milliseconds: 1));
      expect(runs, 2, reason: 'exactly one follow-up for the whole burst');

      await tester.pump(window);
      expect(runs, 2, reason: 'no trigger since, so no further run');
    },
  );

  testWidgets('a trigger during a run that outlasts the window trails it', (
    tester,
  ) async {
    final throttle = TrailingThrottle(window);
    final firstRun = Completer<void>();
    var runs = 0;
    Future<void> action() {
      runs++;
      return runs == 1 ? firstRun.future : Future.value();
    }

    unawaited(throttle.run(action));
    await tester.pump(window * 2);
    unawaited(throttle.run(action));
    await tester.pump();
    expect(runs, 1, reason: 'queued behind the in-flight run');

    firstRun.complete();
    await tester.pump();
    expect(runs, 2);
    // Let the follow-up's own window close before teardown.
    await tester.pump(window);
  });

  testWidgets(
    'a failing run reports to its own caller and still lets the follow-up run',
    (tester) async {
      final throttle = TrailingThrottle(window);
      var runs = 0;
      Future<void> failing() async {
        runs++;
        throw StateError('discovery failed');
      }

      Future<void> ok() async => runs++;

      final first = throttle.run(failing);
      unawaited(throttle.run(ok));
      await expectLater(first, throwsStateError);

      await tester.pump(window);
      expect(runs, 2);
      // Let the follow-up's own window close before teardown.
      await tester.pump(window);
    },
  );
}
