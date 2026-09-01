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

  PangeaHttpException http401(String path, {String? detail, String? body}) =>
      PangeaHttpException.fromResponse(
        Response(
          body ?? '',
          401,
          request: Request('GET', Uri.parse('https://api.pangea.chat$path')),
        ),
        detail: detail,
      );

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

  group('expired-token collapse', () {
    test('all three surfaces land in one grouping', () async {
      for (final e in [choreo, synapseModule, sdk]) {
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
