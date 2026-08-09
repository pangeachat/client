import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';

void main() {
  group('ActivitySummaryModel request timeout', () {
    test('pending request within the timeout is loading, not an error', () {
      // 31s used to trip the old 30s cutoff while the choreographer was
      // still generating (#7660).
      final model = ActivitySummaryModel(
        requestedAt: DateTime.now().subtract(const Duration(seconds: 31)),
      );
      expect(model.hasError, isFalse);
      expect(model.isLoading, isTrue);
    });

    test('pending request past the timeout is an error', () {
      final model = ActivitySummaryModel(
        requestedAt: DateTime.now().subtract(
          ActivitySummaryModel.requestTimeout + const Duration(seconds: 1),
        ),
      );
      expect(model.hasError, isTrue);
      expect(model.isLoading, isFalse);
    });

    test('errorAt marks the model errored regardless of timing', () {
      final model = ActivitySummaryModel(
        requestedAt: DateTime.now(),
        errorAt: DateTime.now(),
      );
      expect(model.hasError, isTrue);
    });
  });

  test(
    'STT-unavailable placeholder matches the choreographer contract string',
    () {
      // Mirrors STT_UNAVAILABLE_PLACEHOLDER in the choreographer's
      // app/infra/matrix/message_schema.py — the summary prompt matches on
      // this exact text.
      expect(
        ActivitySessionConstants.sttUnavailablePlaceholder,
        "[voice message: transcript unavailable]",
      );
    },
  );
}
