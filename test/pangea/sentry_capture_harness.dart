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
  Completer<void>? _sentinelArrived;
  SentryOptions? _options;

  /// The runtime type names of the event processors still installed, so a test
  /// can assert the async enricher is gone without reaching into Sentry's
  /// internal `currentHub`.
  List<String> get activeEventProcessors =>
      _options?.eventProcessors.map((p) => p.runtimeType.toString()).toList() ??
      const [];

  /// Every event reported since [init], for asserting that a path reports
  /// nothing at all.
  final events = <SentryEvent>[];

  Future<void> init() async {
    late SentryOptions captured;
    await Sentry.init((options) {
      captured = options;
      options.dsn = 'https://public@sentry.invalid/1';
      options.beforeSend = (event, hint) {
        events.add(event);
        // Never let a completer throw out of here. Sentry catches an exception
        // from beforeSend and KEEPS the event, which would send it to transport
        // — the one thing this harness exists to prevent.
        try {
          if (event.throwable is _NoReportSentinel) {
            if (_sentinelArrived?.isCompleted == false) {
              _sentinelArrived!.complete();
            }
          } else if (_pending?.isCompleted == false) {
            _pending!.complete(event);
          }
        } catch (_) {
          // silent-ok: a completed completer is not a test failure; the event
          // is already recorded in `events`, which is what assertions read.
        }
        // Dropped: the assertion is on the event, and nothing should leave
        // the test.
        return null;
      };
    });
    _options = captured;
    // Strip the enricher. On Linux it shells out (`cat /proc/meminfo`) BEFORE
    // beforeSend, so two captures can spawn separate processes and finish out of
    // order — which would silently break the barrier [expectNoReport] relies on,
    // on CI only, where nobody watches a green run. With it gone, the path from
    // `captureException` to `beforeSend` is pure microtask work.
    for (final processor in captured.eventProcessors) {
      if (processor.runtimeType.toString().contains('Enricher')) {
        captured.removeEventProcessor(processor);
      }
    }
  }

  Future<void> close() async {
    _pending = null;
    _sentinelArrived = null;
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
  /// [beforeSend]. Anything [work] reported was enqueued first and travels the
  /// identical code path with the identical number of suspension points, so on
  /// a FIFO microtask queue it arrives first too.
  ///
  /// That argument needs the pipeline to contain no I/O, which is why [init]
  /// strips the enricher — on Linux it shells out to `/proc/meminfo` before
  /// `beforeSend`, and two captures racing two processes can finish in either
  /// order. A `Future.delayed` instead of the sentinel would only have moved
  /// the flake somewhere less visible.
  Future<void> expectNoReport(FutureOr<void> Function() work) async {
    final before = events.length;
    await work();
    final arrived = Completer<void>();
    _sentinelArrived = arrived;
    Sentry.captureException(_NoReportSentinel());
    await arrived.future.timeout(const Duration(seconds: 5));
    _sentinelArrived = null;
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
