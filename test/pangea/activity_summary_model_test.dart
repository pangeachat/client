import 'package:flutter_test/flutter_test.dart';

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

  test('reads the fields the bot writes to its canonical slot', () {
    // The bot's pydantic model serializes timestamps with a UTC offset.
    final model = ActivitySummaryModel.fromJson({
      'requested_at': null,
      'error_at': '2026-09-23T12:00:05.123456+00:00',
      'summary': {'participants': [], 'summary': 'Well done.'},
      'lang_code': 'en',
      'call_started_ts': 1790000000000,
    });
    expect(model.summary?.summary, 'Well done.');
    expect(model.errorAt, DateTime.utc(2026, 9, 23, 12, 0, 5, 123, 456));
    expect(model.langCode, 'en');
    expect(model.callStartedTs, 1790000000000);
    expect(model.hasError, isTrue);
  });
}
