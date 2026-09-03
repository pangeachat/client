import 'dart:async';

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
}
