import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'sentry_capture_harness.dart';

/// #9190: an error no caller handled reaches [ErrorHandler.onUncaughtError] —
/// through the zone [ErrorHandler.runGuarded] opens on web — and gets the same
/// grouping as one a repo reports. Before this, web had no working sink, so an
/// unawaited request's failure reached Sentry's browser handler with no
/// grouping key and joined a catch-all issue (CLIENT-B01).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final harness = SentryCaptureHarness();

  setUp(() async {
    ErrorHandler.resetReportedOnceKeysForTest();
    await harness.init();
  });

  tearDown(() => harness.close());

  test('an unawaited dead request lands in the no-response grouping', () async {
    final event = await harness.capture(
      () => ErrorHandler.runGuarded(() {
        // Unawaited, as `room.setTyping` is on every keystroke.
        Future<void>.error(
          ClientException(
            'Failed to fetch',
            Uri.parse(
              'https://matrix.staging.pangea.chat/_matrix/client/v3/rooms/'
              '!r:staging.pangea.chat/typing/@u:staging.pangea.chat',
            ),
          ),
        );
      }, guard: true),
    );
    expect(event.fingerprint, ['pangea-network', 'no-response']);
    expect(event.level, SentryLevel.warning);
  });
}
