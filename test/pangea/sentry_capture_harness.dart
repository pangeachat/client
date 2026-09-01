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

  Future<void> init() => Sentry.init((options) {
    options.dsn = 'https://public@sentry.invalid/1';
    options.beforeSend = (event, hint) {
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
