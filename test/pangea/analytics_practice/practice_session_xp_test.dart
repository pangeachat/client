import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_xp.dart';

/// The completion view shows the XP that counted, and in Objective practice
/// what its Mission gained, read back the way the Mission meters read XP
/// (#9633).
void main() {
  final session = DateTime(2026, 10, 23, 12);

  OneConstructUse use(
    String lemma,
    int xp, {
    ConstructUseTypeEnum? type,
    DateTime? at,
  }) => OneConstructUse(
    useType:
        type ??
        (xp > 0 ? ConstructUseTypeEnum.corLM : ConstructUseTypeEnum.incLM),
    lemma: lemma,
    constructType: ConstructTypeEnum.vocab,
    metadata: ConstructUseMetaData(roomId: null, timeStamp: at ?? session),
    category: 'NOUN',
    form: lemma,
    xp: xp,
  );

  group('PracticeSessionXp.measure', () {
    test('leaves out XP the flower cap kept from counting', () {
      final casa = use('casa', 5);
      final flowered = use('familia', 5, at: session.add(_second));
      // getUses drops the use past familia's cap.
      final xp = PracticeSessionXp.measure(
        sessionUses: [casa, flowered],
        learnerUses: [casa],
      );
      expect(xp.counted, 5);
      expect(xp.missionGain, isNull);
    });

    test('counts none of the learner\'s other uses', () {
      final casa = use('casa', 5);
      final xp = PracticeSessionXp.measure(
        sessionUses: [casa],
        learnerUses: [
          use('casa', 20, at: session.subtract(const Duration(days: 1))),
          casa,
          use('perro', 3, type: ConstructUseTypeEnum.wa),
        ],
      );
      expect(xp.counted, 5);
    });

    test('matches a use to the millisecond the store keeps', () {
      final answered = use(
        'casa',
        5,
        at: DateTime(2026, 10, 23, 12, 0, 0, 7, 456),
      );
      final stored = use('casa', 5, at: DateTime(2026, 10, 23, 12, 0, 0, 7));
      expect(
        PracticeSessionXp.measure(
          sessionUses: [answered],
          learnerUses: [stored],
        ).counted,
        5,
      );
    });

    test('two bonuses that look alike are each counted once', () {
      final bonus = use('casa', 1, type: ConstructUseTypeEnum.bonus);
      expect(
        PracticeSessionXp.measure(
          sessionUses: [bonus, bonus],
          learnerUses: [bonus, bonus, bonus],
        ).counted,
        2,
      );
    });

    test('a Mission gains its own words, not the rest of a read-aloud '
        'sentence', () {
      final casa = use('casa', 5);
      final heard = use('perro', 4, type: ConstructUseTypeEnum.pvm);
      final xp = PracticeSessionXp.measure(
        sessionUses: [casa, heard],
        learnerUses: [casa, heard],
        missionLemmas: {'casa', 'familia'},
      );
      expect(xp.counted, 9);
      expect(xp.missionGain, 5);
    });

    test('a Mission gains what lifts a word above zero (#9607)', () {
      final earlier = session.subtract(const Duration(days: 1));
      final casa = use('casa', 5);
      final xp = PracticeSessionXp.measure(
        sessionUses: [casa],
        learnerUses: [
          for (var i = 0; i < 3; i++) use('casa', -1, at: earlier),
          casa,
        ],
        missionLemmas: {'casa'},
      );
      expect(xp.counted, 5);
      expect(xp.missionGain, 2);
    });
  });

  group('session bonus uses', () {
    AnalyticsPracticeSessionModel finished() {
      final model = AnalyticsPracticeSessionModel(
        type: ConstructTypeEnum.vocab,
        practiceTargets: const [],
        userL1: 'en',
        userL2: 'es',
      );
      model.submitAnswer([use('casa', 5), use('familia', -1)]);
      model.finishSession();
      return model;
    }

    test('are fixed when the session finishes', () {
      final model = finished();
      final recorded = model.state.bonusUses;
      // Accuracy is under 100% and the clock is at zero: the speed bonus
      // only, one per correct answer.
      expect(recorded, hasLength(1));
      expect(identical(model.state.bonusUses, recorded), isTrue);
      expect(model.state.recordedUses, hasLength(3));
    });

    test('survive a save and restore with their timestamps', () {
      final model = finished();
      final restored = AnalyticsPracticeSessionState.fromJson(
        model.state.toJson(),
      );
      expect(
        restored.bonusUses.single.timeStamp.isAtSameMomentAs(
          model.state.bonusUses.single.timeStamp,
        ),
        isTrue,
      );
    });
  });
}

const _second = Duration(seconds: 1);
