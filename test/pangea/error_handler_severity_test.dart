import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'sentry_capture_harness.dart';

/// The severity a report reaches Sentry with, asserted where it is actually
/// decided — [ErrorHandler.logError] — rather than on the table in isolation.
///
/// #8369: the table exists ([PangeaHttpException.severityOf]) but only the
/// repos that pass `level:` were applying it, so a routine 401 raised anywhere
/// else still arrived as `error`. These tests pin the default to the table, and
/// pin that an explicit level still wins — a caller with context may escalate,
/// per repos-and-error-handling.instructions.md § The contract. The grouping
/// the same sink applies is pinned in error_handler_fingerprint_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final harness = SentryCaptureHarness();

  setUp(() async {
    ErrorHandler.resetReportedOnceKeysForTest();
    await harness.init();
  });

  tearDown(() => harness.close());

  /// The level of the single event [report] produces.
  Future<SentryLevel?> levelOf(void Function() report) async =>
      (await harness.capture(report)).level;

  PangeaHttpException http(int status) => PangeaHttpException.fromResponse(
    Response(
      '',
      status,
      request: Request('GET', Uri.parse('https://api.pangea.chat/x')),
    ),
  );

  group('ErrorHandler.logError default level', () {
    test('a routine 401 is a warning, not an error', () async {
      expect(
        await levelOf(() => ErrorHandler.logError(e: http(401), data: {})),
        SentryLevel.warning,
      );
    });

    test('404, 410, and 429 are warnings', () async {
      for (final status in [404, 410, 429]) {
        expect(
          await levelOf(() => ErrorHandler.logError(e: http(status), data: {})),
          SentryLevel.warning,
          reason: '$status should be a warning',
        );
      }
    });

    test('a timeout is a warning', () async {
      expect(
        await levelOf(
          () => ErrorHandler.logError(e: TimeoutException('slow'), data: {}),
        ),
        SentryLevel.warning,
      );
    });

    test(
      '403 stays an error — we asked for something we should not have',
      () async {
        expect(
          await levelOf(() => ErrorHandler.logError(e: http(403), data: {})),
          SentryLevel.error,
        );
      },
    );

    test('other 4xx and all 5xx stay errors', () async {
      for (final status in [400, 405, 422, 500, 502, 504]) {
        expect(
          await levelOf(() => ErrorHandler.logError(e: http(status), data: {})),
          SentryLevel.error,
          reason: '$status should be an error',
        );
      }
    });

    test('a non-HTTP failure stays an error', () async {
      expect(
        await levelOf(
          () => ErrorHandler.logError(e: Exception('parse'), data: {}),
        ),
        SentryLevel.error,
      );
    });

    test('a non-HTTP exception stays an error', () async {
      expect(
        await levelOf(
          () => ErrorHandler.logError(e: Exception('no exception'), data: {}),
        ),
        SentryLevel.error,
      );
    });
  });

  group('ErrorHandler explicit level', () {
    test(
      'an explicit level wins over the table — callers may escalate',
      () async {
        expect(
          await levelOf(
            () => ErrorHandler.logError(
              e: http(401),
              data: {},
              level: SentryLevel.error,
            ),
          ),
          SentryLevel.error,
        );
      },
    );

    test('an explicit level can also lower a 500', () async {
      expect(
        await levelOf(
          () => ErrorHandler.logError(
            e: http(500),
            data: {},
            level: SentryLevel.info,
          ),
        ),
        SentryLevel.info,
      );
    });
  });

  group('ErrorHandler.logErrorOnce', () {
    test('applies the same default table', () async {
      expect(
        await levelOf(
          () => ErrorHandler.logErrorOnce(key: 'k401', e: http(401), data: {}),
        ),
        SentryLevel.warning,
      );
    });

    test('still honors an explicit level', () async {
      expect(
        await levelOf(
          () => ErrorHandler.logErrorOnce(
            key: 'k401-escalated',
            e: http(401),
            data: {},
            level: SentryLevel.error,
          ),
        ),
        SentryLevel.error,
      );
    });
  });
}
