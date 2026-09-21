import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Captures the single [SentryEvent] a report produces, without letting it
/// leave the test.
///
/// Shared by the suites that assert what `ErrorHandler` puts on the scope.
/// Severity and grouping are both decided at that one sink, so both are
/// asserted on the event it actually produces rather than on the tables in
/// isolation.
class SentryCaptureHarness {
  Completer<SentryEvent>? _pending;

  /// Every event reported since [init], for asserting that a path reports
  /// nothing at all.
  final events = <SentryEvent>[];

  Future<void> init() => Sentry.init((options) {
    options.dsn = 'https://public@sentry.invalid/1';
    options.beforeSend = (event, hint) {
      events.add(event);
      _pending?.complete(event);
      // Dropped: the assertion is on the event, and nothing should leave
      // the test.
      return null;
    };
  });

  Future<void> close() async {
    _pending = null;
    await Sentry.close();
  }

  /// The single event [report] produces.
  Future<SentryEvent> capture(void Function() report) {
    final completer = Completer<SentryEvent>();
    _pending = completer;
    report();
    return completer.future.timeout(const Duration(seconds: 5));
  }

  /// Asserts [work] reported NOTHING, without the race that `expect(events,
  /// isEmpty)` carries.
  ///
  /// `ErrorHandler.logError` calls `Sentry.captureException` and does not await
  /// it, so [beforeSend] runs several turns after the code that reported. A bare
  /// `expect(events, isEmpty)` therefore passes in two different situations —
  /// nothing was reported, and something was reported but has not arrived yet.
  /// The second is a false green, the direction that hides a regression:
  /// client#8742 merged with CI green while carrying the bug those assertions
  /// existed to catch (pangeachat/.github#460).
  ///
  /// Ordering is what makes this sound, not a delay. After [work] runs, this
  /// reports a sentinel of its own and waits for the sentinel to reach
  /// [beforeSend]. Any event [work] enqueued was enqueued first, so once the
  /// sentinel has arrived, anything real has arrived too — and the queue is
  /// pure async here, because the harness's [beforeSend] drops every event
  /// before transport and no I/O reorders the chain. A fixed `Future.delayed`
  /// would only move the flake, not remove it.
  Future<void> expectNoReport(FutureOr<void> Function() work) async {
    final before = events.length;
    await work();
    final sentinel = _NoReportSentinel();
    await capture(() => Sentry.captureException(sentinel));
    final unexpected = events
        .skip(before)
        .where((e) => e.throwable is! _NoReportSentinel)
        .toList();
    if (unexpected.isNotEmpty) {
      fail(
        'expected nothing to be reported to Sentry, but '
        '${unexpected.length} event(s) were: '
        '${unexpected.map((e) => e.throwable ?? e.exceptions).join(', ')}',
      );
    }
  }
}

/// Reported by [SentryCaptureHarness.expectNoReport] to mark the end of the
/// queue. Never produced by app code.
class _NoReportSentinel implements Exception {
  @override
  String toString() => 'SentryCaptureHarness.expectNoReport sentinel';
}

/// Counts the Sentry events a stretch of work produces, without letting any
/// leave the test.
///
/// The counterpart of [SentryCaptureHarness], which answers what ONE event
/// carried. The question here is how MANY, and it is the only way to pin a
/// throttle: a report that fires per failure and a report that fires once are
/// the same single event when you only look at the first one.
class SentryEventCounter {
  int events = 0;

  Future<void> init() {
    events = 0;
    return Sentry.init((options) {
      options.dsn = 'https://public@sentry.invalid/1';
      // OFF, so this counts what the CODE emits rather than what the SDK
      // happens to swallow. Sentry drops a repeat of the same exception by
      // default, which quietly makes an unthrottled report look throttled —
      // it did, on the first version of the roster's budget test. The
      // deduplication is a small ring buffer keyed on the exception, so
      // relying on it would be relying on a failure always arriving as the
      // same object, which across a whole call it does not.
      options.enableDeduplication = false;
      options.beforeSend = (event, hint) {
        events++;
        // Dropped: nothing should leave the test.
        return null;
      };
    });
  }

  Future<void> close() => Sentry.close();
}
