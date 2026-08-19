import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// One failure, one Sentry event, raised through the one sink.
///
/// repos-and-error-handling.instructions.md § The contract states a failure is
/// captured "exactly once", and § Severity policy puts severity at the sink
/// rather than the call site. A call site that reaches `Sentry` directly
/// silently opts out of both — plus the fingerprint (#8469) — and the diff
/// looks like extra diligence rather than a defect.
///
/// That miss has now happened three times: `FlutterError.onError` (#8469) and
/// the `setReadMarker` handler (#8476), which additionally wrapped the error in
/// a `PangeaWarningError("...$e")` and so stringified away the very type the
/// severity table reads. A rule enforced by review drifts; this one is pinned.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the sink is the only way to Sentry', () {
    /// [source] with whole-line comments removed, so a doc comment *about*
    /// `Sentry.captureException` is not mistaken for a call to it — this file
    /// and the fixed handler both discuss it in prose.
    String withoutCommentLines(String source) => source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    List<String> callersOf(String needle) =>
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where(
              (f) => withoutCommentLines(f.readAsStringSync()).contains(needle),
            )
            .map((f) => f.path)
            .toList()
          ..sort();

    test('no call site captures to Sentry directly', () {
      expect(
        callersOf('Sentry.captureException('),
        [
          // The sink itself: where severity, the fingerprint, and the
          // UnsubscribedException guard are applied.
          'lib/pangea/common/utils/error_handler.dart',
          // Not an error report — a user deliberately reporting a message,
          // carrying its own fingerprint. It has no failure to severitize.
          'lib/routes/chat/events/utils/report_message.dart',
        ],
        reason:
            'A new direct capture bypasses the severity table and the '
            'fingerprint. Report through ErrorHandler.logError instead; if '
            'this genuinely is not an error report, add it above with why.',
      );
    });
  });

  group('a read-marker failure', () {
    late List<SentryEvent> captured;
    Completer<void>? firstEvent;

    setUp(() async {
      captured = [];
      firstEvent = Completer<void>();
      ErrorHandler.resetReportedOnceKeysForTest();
      await Sentry.init((options) {
        options.dsn = 'https://public@sentry.invalid/1';
        options.beforeSend = (event, hint) {
          captured.add(event);
          if (firstEvent?.isCompleted == false) firstEvent!.complete();
          // Dropped: the assertion is on the event, and nothing should leave
          // the test.
          return null;
        };
      });
    });

    tearDown(() async {
      firstEvent = null;
      await Sentry.close();
    });

    /// What `timeline.setReadMarker` actually throws — a Matrix SDK failure,
    /// not a [PangeaHttpException].
    MatrixException matrixFailure() => MatrixException.fromJson({
      'errcode': 'M_FORBIDDEN',
      'error': 'You are not in the room',
    });

    /// Reports [failure], then waits for the event to reach `beforeSend`.
    /// [ErrorHandler.logError] does not await its own capture, so awaiting the
    /// call is not enough — the existing severity suite waits the same way.
    Future<void> report(Object failure, Map<String, dynamic> data) async {
      await ErrorHandler.logError(
        e: failure,
        s: StackTrace.current,
        data: data,
      );
      await firstEvent!.future.timeout(const Duration(seconds: 5));
      // Settle, so a second capture would be counted rather than raced past.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    test('reports once, not twice', () async {
      await report(matrixFailure(), {'where': 'setReadMarker'});
      expect(captured, hasLength(1));
    });

    test('reaches Sentry with its type intact, not stringified', () async {
      final failure = matrixFailure();
      await report(failure, {'where': 'setReadMarker'});

      // The wrapper this site used to apply produced a plain
      // `PangeaWarningError` whose message was the failure's toString(). The
      // severity table and the fingerprint both read the exception, so a
      // wrapped failure is unreadable to either.
      expect(captured.single.throwable, same(failure));
    });

    test('carries the call site as breadcrumb context', () async {
      await report(matrixFailure(), {
        'where': 'setReadMarker',
        'eventId': r'$event',
        'roomId': '!room',
      });

      // `where` was a Sentry tag set by the second, raw capture. Severity and
      // grouping belong to the sink; call-site context rides in `data`, which
      // is the channel logError already had.
      final data = captured.single.breadcrumbs?.last.data;
      expect(data?['where'], 'setReadMarker');
      expect(data?['roomId'], '!room');
    });
  });
}
