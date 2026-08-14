import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// CLIENT-E4T (#8373): `UnsubscribedException` is control flow — an
/// unsubscribed user hitting a paid endpoint — and
/// repos-and-error-handling.instructions.md says it is *never* reported. It
/// reached production Sentry anyway, titled `Instance of
/// 'UnsubscribedException'`, because the `is! UnsubscribedException` guard was
/// copied into four call sites while a dozen other paths (hand-rolled repos
/// that bypass [BaseRepo], `showFutureLoadingDialog`, and the global
/// unhandled-async sink) had no guard at all. These pin both halves of the fix:
/// the invariant enforced once at the reporting sink, and a diagnosable
/// `toString()` as the backstop.
void main() {
  test('UnsubscribedException has a diagnosable toString', () {
    expect(
      UnsubscribedException().toString(),
      'UnsubscribedException: no active subscription (401)',
    );
  });

  group('ErrorHandler.shouldReport', () {
    test('an unsubscribed user is control flow, never reported', () {
      expect(ErrorHandler.shouldReport(UnsubscribedException()), isFalse);
    });

    test('a real HTTP failure is still reported', () {
      expect(
        ErrorHandler.shouldReport(
          PangeaHttpException(
            statusCode: 500,
            method: 'GET',
            path: '/lemma/{id}',
          ),
        ),
        isTrue,
      );
    });

    test('an untyped failure is still reported', () {
      expect(
        ErrorHandler.shouldReport(Exception('choreo unreachable')),
        isTrue,
      );
    });

    test('a message-only report with no exception is still reported', () {
      expect(ErrorHandler.shouldReport(null), isTrue);
    });
  });

  group('ErrorHandler.logErrorOnce', () {
    setUp(ErrorHandler.resetReportedOnceKeysForTest);
    tearDown(ErrorHandler.resetReportedOnceKeysForTest);

    test(
      'does not report an unsubscribed user, and does not burn the key',
      () async {
        expect(
          await ErrorHandler.logErrorOnce(
            key: 'course-outline-resolve:c1',
            e: UnsubscribedException(),
            data: {'courseUuid': 'c1'},
          ),
          isFalse,
        );

        // The key is still available — suppressing control flow must not spend
        // the one report a genuine failure on this key is owed.
        expect(
          await ErrorHandler.logErrorOnce(
            key: 'course-outline-resolve:c1',
            e: Exception('choreo unreachable'),
            data: {'courseUuid': 'c1'},
          ),
          isTrue,
        );
      },
    );
  });
}
