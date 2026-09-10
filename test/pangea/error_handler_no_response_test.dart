import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'sentry_capture_harness.dart';

/// #8890: a request that never reached a server — offline, DNS, CORS, a
/// blocked request — arrives as a [ClientException] with no status. It fails
/// every surface at once, so it collapses like the expired token (#8698): one
/// grouping, one report per app session, warning per the severity table's
/// no-response row. Before this, one learner offline for seven seconds
/// produced ten flag reports (CLIENT-EGM) inside a 3,588-event catch-all
/// (CLIENT-5XY).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final harness = SentryCaptureHarness();

  setUp(() async {
    ErrorHandler.resetReportedOnceKeysForTest();
    await harness.init();
  });

  tearDown(() => harness.close());

  ClientException noResponse(String url) =>
      ClientException('Failed to fetch', Uri.parse(url));

  group('no-response collapse', () {
    test('lands in one grouping at warning', () async {
      final event = await harness.capture(
        () => ErrorHandler.logError(
          e: noResponse(
            'https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/'
            'language-flags/de.svg',
          ),
          data: {},
        ),
      );
      expect(event.fingerprint, ['pangea-network', 'no-response']);
      expect(event.level, SentryLevel.warning);
    });

    test('a second dead request in the same session adds no event, '
        'whatever it was for', () async {
      await harness.capture(
        () => ErrorHandler.logError(
          e: noResponse('https://api.pangea.chat/choreo/v2/activity/x'),
          data: {},
        ),
      );

      // The suppressed reports produce nothing, so the next event the scope
      // sees must be the sentinel that follows them.
      final next = await harness.capture(() {
        ErrorHandler.logError(
          e: noResponse(
            'https://admin-dash-api.pangea.chat/api/internal/dosage/'
            'audio-signals',
          ),
          data: {},
        );
        ErrorHandler.logErrorOnce(
          key: 'svg:bg',
          e: noResponse('https://example.invalid/language-flags/bg.svg'),
          data: {},
        );
        ErrorHandler.logError(e: Exception('sentinel'), data: {});
      });
      expect(next.throwable.toString(), contains('sentinel'));
    });

    test('a failure with no status but a response is not capped', () async {
      final first = await harness.capture(
        () => ErrorHandler.logError(e: Exception('parse'), data: {}),
      );
      final second = await harness.capture(
        () => ErrorHandler.logError(e: Exception('parse'), data: {}),
      );
      expect(first.level, SentryLevel.error);
      expect(second.level, SentryLevel.error);
    });
  });
}
