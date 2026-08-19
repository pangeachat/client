import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'sentry_capture_harness.dart';

/// One of the production quest ids behind CLIENT-DWD, kept whole so the
/// normalization the fingerprint depends on is exercised, not assumed.
const _questId = '349d9dec-fd61-4469-94e2-81b2faecbbd1';

/// The Sentry grouping key a report reaches Sentry with, asserted where it is
/// actually decided — [ErrorHandler.logError] — rather than on the table in
/// isolation.
///
/// #8469: Sentry groups by stack trace, and every [PangeaHttpException] is
/// raised through one frame in `Requests`, so a routine 404 for a removed
/// activity, a 401 token refresh and a 5xx backend regression all landed in
/// one catch-all issue (CLIENT-DWD) — one status, one assignee, one ignore
/// switch. These tests pin the fingerprint that splits that per endpoint
/// failure mode, and pin that it does NOT split per resource.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final harness = SentryCaptureHarness();

  setUp(() async {
    ErrorHandler.resetReportedOnceKeysForTest();
    await harness.init();
  });

  tearDown(() => harness.close());

  /// The fingerprint of the single event [report] produces.
  Future<List<String>?> fingerprintOf(void Function() report) async =>
      (await harness.capture(report)).fingerprint;

  PangeaHttpException http(
    int status, {
    String method = 'GET',
    String path = '/choreo/v2/activities/bbox',
    String? detail,
  }) => PangeaHttpException.fromResponse(
    Response(
      '',
      status,
      request: Request(method, Uri.parse('https://api.pangea.chat$path')),
    ),
    detail: detail,
  );

  group('ErrorHandler.logError fingerprint', () {
    test('groups by status, method, and endpoint', () async {
      expect(
        await fingerprintOf(
          () => ErrorHandler.logError(
            e: http(
              404,
              path: '/choreo/v2/activity/98881d89-7195-4928-95ad-3aef0ec3228a',
            ),
            data: {},
          ),
        ),
        ['pangea-http', '404', 'GET', '/choreo/v2/activity/{id}'],
      );
    });

    test('a 5xx does not share the 404 group on the same endpoint', () async {
      final notFound = await fingerprintOf(
        () => ErrorHandler.logError(
          e: http(404, path: '/choreo/quests/$_questId/activities'),
          data: {},
        ),
      );
      final failed = await fingerprintOf(
        () => ErrorHandler.logError(
          e: http(503, path: '/choreo/quests/$_questId/activities'),
          data: {},
        ),
      );
      expect(notFound, isNot(failed));
    });

    test('two endpoints failing the same way do not share a group', () async {
      final subscription = await fingerprintOf(
        () => ErrorHandler.logError(
          e: http(401, path: '/subscription/status'),
          data: {},
        ),
      );
      final constructs = await fingerprintOf(
        () => ErrorHandler.logError(
          e: http(401, method: 'POST', path: '/choreo/grammar_constructs'),
          data: {},
        ),
      );
      expect(subscription, isNot(constructs));
    });

    test(
      'two resources under one endpoint share a group — detail never splits',
      () async {
        final first = await fingerprintOf(
          () => ErrorHandler.logError(
            e: http(
              404,
              path: '/choreo/v2/activity/1eb96fee-756f-4522-91cf-6ec9ad1a6e85',
              detail:
                  "No canonical activity found for activity_id="
                  "'1eb96fee-756f-4522-91cf-6ec9ad1a6e85'",
            ),
            data: {},
          ),
        );
        final second = await fingerprintOf(
          () => ErrorHandler.logError(
            e: http(
              404,
              path: '/choreo/v2/activity/2a3c40b7-8a00-445e-8bea-18d13404fab9',
              detail:
                  "No canonical activity found for activity_id="
                  "'2a3c40b7-8a00-445e-8bea-18d13404fab9'",
            ),
            data: {},
          ),
        );
        expect(first, second);
      },
    );

    test('a non-HTTP failure keeps Sentry default grouping', () async {
      expect(
        await fingerprintOf(
          () => ErrorHandler.logError(e: Exception('parse'), data: {}),
        ),
        anyOf(isNull, isEmpty),
      );
    });

    test('a message-only report keeps Sentry default grouping', () async {
      expect(
        await fingerprintOf(
          () => ErrorHandler.logError(m: 'no exception', data: {}),
        ),
        anyOf(isNull, isEmpty),
      );
    });
  });

  group('ErrorHandler.logErrorOnce fingerprint', () {
    test('carries the same fingerprint as logError', () async {
      expect(
        await fingerprintOf(
          () => ErrorHandler.logErrorOnce(
            key: 'quest-activities-503',
            e: http(503, path: '/choreo/quests/$_questId/activities'),
            data: {},
          ),
        ),
        ['pangea-http', '503', 'GET', '/choreo/quests/{id}/activities'],
      );
    });
  });
}
