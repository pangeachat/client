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

  test('the enricher is stripped, so no I/O can reorder the pipeline', () {
    // The barrier argument depends on this. If a future SDK renames the
    // processor or adds another async one, this fails here rather than flaking
    // on Linux CI, where nobody is watching a run that is already green.
    final names = sentry.activeEventProcessors;
    expect(
      names.where((n) => n.contains('Enricher')),
      isEmpty,
      reason: 'an async enricher would break expectNoReport ordering: $names',
    );
  });

  test(
    'a real report arriving first does not break the sentinel wait',
    () async {
      // Guards the completer reuse: if an unawaited real report completed the
      // sentinel's waiter, the sentinel would complete it again, throw out of
      // beforeSend, and Sentry would KEEP the event and send it.
      await expectLater(
        () => sentry.expectNoReport(() {
          Sentry.captureException(StateError('first'));
          Sentry.captureException(StateError('second'));
        }),
        throwsA(isA<TestFailure>()),
      );
      // Still usable afterwards — nothing was left half-completed.
      await sentry.expectNoReport(() {});
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
