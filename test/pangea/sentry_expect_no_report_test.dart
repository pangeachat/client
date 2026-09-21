import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sentry_capture_harness.dart';

/// Covers pangeachat/.github#460: `expect(sentry.events, isEmpty)` passes both
/// when nothing was reported AND when something was reported but has not
/// arrived yet, because `ErrorHandler.logError` does not await the capture.
/// The second is a false green — client#8742 merged with CI green while
/// carrying the bug the assertion existed to catch.
///
/// These tests pin BOTH directions of `expectNoReport`. The negative direction
/// is the one that matters: a helper that only ever passes would be the same
/// false green wearing a better name.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SentryCaptureHarness sentry;

  setUp(() async {
    sentry = SentryCaptureHarness();
    await sentry.init();
  });

  tearDown(() => sentry.close());

  test('passes when the work reports nothing', () async {
    await sentry.expectNoReport(() {});
  });

  test('passes when the work is async and reports nothing', () async {
    await sentry.expectNoReport(() async {
      await Future<void>.delayed(Duration.zero);
    });
  });

  test(
    'FAILS on a report that has not arrived when the work returns',
    () async {
      // The exact racy shape: fire and do not await. `expect(events, isEmpty)`
      // here passes; expectNoReport must not.
      await expectLater(
        () => sentry.expectNoReport(() {
          Sentry.captureException(StateError('late report'));
        }),
        throwsA(isA<TestFailure>()),
      );
    },
  );

  test(
    'a bare isEmpty assertion would have passed on that same shape',
    () async {
      // Pins WHY the helper exists. If this ever starts failing, the SDK has
      // become synchronous and the helper's rationale needs revisiting.
      Sentry.captureException(StateError('late report'));
      expect(
        sentry.events,
        isEmpty,
        reason: 'the racy assertion passes here — that is the false green',
      );
    },
  );

  test(
    'reports the throwable it caught, so a failure is diagnosable',
    () async {
      try {
        await sentry.expectNoReport(() {
          Sentry.captureException(StateError('boom-marker'));
        });
        fail('expectNoReport should have failed');
      } on TestFailure catch (e) {
        expect(e.message, contains('boom-marker'));
      }
    },
  );
}
