import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';

/// The practice clock's zero is the first exercise on screen, not the moment
/// the session's targets were selected — a slow first generation must not
/// spend the learner's speed bonus (#8966). See
/// practice-exercises.instructions.md § Loading & Generation Sequencing.
void main() {
  AnalyticsPracticeSessionModel session() => AnalyticsPracticeSessionModel(
    type: ConstructTypeEnum.vocab,
    practiceTargets: const [],
    userL1: 'en',
    userL2: 'de',
  );

  group('practice session clock', () {
    test('has not started when the session is built', () {
      expect(session().startedAt, isNull);
    });

    test('markStarted stamps the clock', () {
      final model = session();
      final before = DateTime.now();
      model.markStarted();

      expect(model.startedAt, isNotNull);
      expect(
        model.startedAt!.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('markStarted is idempotent — later exercises never restart it', () {
      final model = session();
      model.markStarted();
      final first = model.startedAt;

      model.markStarted();
      expect(model.startedAt, first);
    });
  });
}
