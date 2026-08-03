import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

void main() {
  // #8083: known recurring degrade paths (an orphaned course's quest plan,
  // retried on every sync / panel open) report once per session per key —
  // the first event carries the signal; repeats are pure Sentry volume.
  // Sentry is uninitialized here, so captures no-op — these tests pin the
  // dedupe contract only.
  group('ErrorHandler.logErrorOnce', () {
    setUp(ErrorHandler.resetReportedOnceKeysForTest);
    tearDown(ErrorHandler.resetReportedOnceKeysForTest);

    test('reports the first call for a key, suppresses repeats', () async {
      expect(
        await ErrorHandler.logErrorOnce(
          key: 'course-outline-resolve:c1',
          e: Exception('missing quest'),
          data: {'courseUuid': 'c1'},
        ),
        isTrue,
      );
      expect(
        await ErrorHandler.logErrorOnce(
          key: 'course-outline-resolve:c1',
          e: Exception('missing quest'),
          data: {'courseUuid': 'c1'},
        ),
        isFalse,
      );
    });

    test('distinct keys report independently', () async {
      await ErrorHandler.logErrorOnce(
        key: 'course-outline-resolve:c1',
        e: Exception('missing quest'),
        data: {'courseUuid': 'c1'},
      );
      expect(
        await ErrorHandler.logErrorOnce(
          key: 'course-outline-resolve:c2',
          e: Exception('missing quest'),
          data: {'courseUuid': 'c2'},
        ),
        isTrue,
      );
    });
  });
}
