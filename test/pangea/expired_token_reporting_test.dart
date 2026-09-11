import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'sentry_capture_harness.dart';

/// The choreo auth layer's detail when Synapse rejects the bearer during its
/// WhoAmI validation — the exact string production 401s carry (CLIENT-EBG).
const _whoAmIDetail =
    'Matrix WhoAmI API request failed: Matrix WhoAmI non-200 (401)';

const _uuid = '2e0d6c1e-4f2a-4b6b-9c3d-0a1b2c3d4e5f';

/// #8698: one expired Matrix token fails every surface at once — parallel
/// calls at app boot 401 before the SDK's soft-logout refresh lands — and
/// scattered into seven per-endpoint Sentry issues (CLIENT-EHD, -EBG, -EBK,
/// -EBM, -EBH, -EED, -EBJ). These tests pin the collapse: one grouping, one
/// report per app session, and every other 401 untouched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final harness = SentryCaptureHarness();

  setUp(() async {
    ErrorHandler.resetReportedOnceKeysForTest();
    await harness.init();
  });

  tearDown(() => harness.close());

  PangeaHttpException http(
    int status,
    String path, {
    String method = 'GET',
    String? detail,
  }) => PangeaHttpException.fromResponse(
    Response(
      '',
      status,
      request: Request(method, Uri.parse('https://api.pangea.chat$path')),
    ),
    detail: detail,
  );

  PangeaHttpException http401(String path, {String? detail}) =>
      http(401, path, detail: detail);

  final choreo = http401('/choreo/v2/activities/bbox', detail: _whoAmIDetail);
  final synapseModule = http401(
    '/_synapse/client/pangea/v1/activity_session_previews',
    detail: 'M_UNAUTHORIZED',
  );
  final sdk = MatrixException.fromJson({
    'errcode': 'M_UNKNOWN_TOKEN',
    'error': 'Access token has expired',
    'soft_logout': true,
  });
  // The CMS answers a rejected bearer with Payload's generic 403 and no
  // detail — its Matrix auth strategy swallows Synapse's 401 into "no user"
  // and the read rule then denies — so the same boot burst lands one hop
  // later as a 403 on a read (CLIENT-EBF, #8372).
  final cmsRead = http(403, '/cms/api/quest-plans/$_uuid');

  group('expired-token collapse', () {
    test('every surface lands in one grouping', () async {
      for (final e in [choreo, synapseModule, sdk, cmsRead]) {
        ErrorHandler.resetReportedOnceKeysForTest();
        final event = await harness.capture(
          () => ErrorHandler.logError(e: e, data: {}),
        );
        expect(event.fingerprint, ['pangea-auth', 'expired-matrix-token']);
      }
    });

    test(
      'a second surface failing in the same session adds no event',
      () async {
        await harness.capture(() => ErrorHandler.logError(e: choreo, data: {}));

        // The suppressed report produces nothing, so the next event the scope
        // sees must be the sentinel that follows it.
        final next = await harness.capture(() {
          ErrorHandler.logError(e: synapseModule, data: {});
          ErrorHandler.logError(e: sdk, data: {});
          ErrorHandler.logError(e: cmsRead, data: {});
          ErrorHandler.logError(e: Exception('sentinel'), data: {});
        });
        expect(next.throwable.toString(), contains('sentinel'));
      },
    );

    test('reports as warning — token lifecycle is routine', () async {
      final event = await harness.capture(
        () => ErrorHandler.logError(e: sdk, data: {}),
      );
      expect(event.level, SentryLevel.warning);
    });

    test('a 401 without the expired-token shape keeps per-endpoint grouping '
        'and is not capped', () async {
      final first = await harness.capture(
        () =>
            ErrorHandler.logError(e: http401('/subscription/status'), data: {}),
      );
      expect(first.fingerprint, [
        'pangea-http',
        '401',
        'GET',
        '/subscription/status',
      ]);

      // A fresh instance: Sentry's own dedupe drops a repeated throwable
      // instance, which is not the cap under test.
      final second = await harness.capture(
        () =>
            ErrorHandler.logError(e: http401('/subscription/status'), data: {}),
      );
      expect(second.fingerprint, first.fingerprint);
    });

    test('a CMS read denied 403 is the token, not a permission bug', () async {
      final event = await harness.capture(
        () => ErrorHandler.logError(e: cmsRead, data: {}),
      );
      expect(event.fingerprint, ['pangea-auth', 'expired-matrix-token']);
      expect(event.level, SentryLevel.warning);
    });

    // Negative controls: the carve-out is a CMS *read*. A write's rules are
    // per-role, and nothing outside the CMS answers a rejected bearer with a
    // 403, so both keep the 403 row — per-endpoint grouping at error.
    test(
      'a CMS write 403 and a non-CMS 403 keep per-endpoint error grouping',
      () async {
        final cmsWrite = http(403, '/cms/api/quest-plans', method: 'POST');
        final choreo403 = http(403, '/choreo/v2/activity/$_uuid');
        for (final (e, fingerprint) in [
          (cmsWrite, ['pangea-http', '403', 'POST', '/cms/api/quest-plans']),
          (
            choreo403,
            ['pangea-http', '403', 'GET', '/choreo/v2/activity/{id}'],
          ),
        ]) {
          final event = await harness.capture(
            () => ErrorHandler.logError(e: e, data: {}),
          );
          expect(event.fingerprint, fingerprint);
          expect(event.level, SentryLevel.error);
        }
      },
    );

    test(
      'a non-M_UNKNOWN_TOKEN MatrixException keeps default grouping',
      () async {
        final forbidden = MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'You are not invited to this room',
        });
        final event = await harness.capture(
          () => ErrorHandler.logError(e: forbidden, data: {}),
        );
        expect(event.fingerprint, anyOf(isNull, isEmpty));
      },
    );
  });
}
