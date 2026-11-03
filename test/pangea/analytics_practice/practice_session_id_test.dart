import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';

OneConstructUse _use(String lemma, int xp, {String? sessionId}) =>
    OneConstructUse(
      useType: xp > 0 ? ConstructUseTypeEnum.corPA : ConstructUseTypeEnum.incPA,
      lemma: lemma,
      constructType: ConstructTypeEnum.vocab,
      metadata: ConstructUseMetaData(
        roomId: null,
        timeStamp: DateTime.utc(2026, 11, 1, 12),
        sessionId: sessionId,
      ),
      category: 'noun',
      form: lemma,
      xp: xp,
    );

AnalyticsPracticeSessionModel _session() => AnalyticsPracticeSessionModel(
  type: ConstructTypeEnum.vocab,
  practiceTargets: const [],
  userL1: 'en',
  userL2: 'es',
);

void main() {
  group('the practice session id on a use', () {
    test('is written only when there is one, and reads back', () {
      final json = _use('casa', 5, sessionId: 's1').toJson();
      expect(json['sessionId'], 's1');
      expect(OneConstructUse.fromJson(json).metadata.sessionId, 's1');
      expect(_use('casa', 5).toJson().containsKey('sessionId'), isFalse);
    });

    test('an old use, or one with a bad value, reads as none', () {
      final old = _use('casa', 5).toJson();
      expect(OneConstructUse.fromJson(old).metadata.sessionId, isNull);
      final bad = {...old, 'sessionId': 7};
      expect(OneConstructUse.fromJson(bad).metadata.sessionId, isNull);
    });

    test('changes nothing else about a use', () {
      final plain = _use('casa', 5).toJson();
      final stamped = _session().ownUses([_use('casa', 5)]).single.toJson();
      expect({...stamped}..remove('sessionId'), plain);
    });
  });

  group('a practice session', () {
    test('stamps its answers and their bonuses with its id', () {
      final model = _session();
      model.submitAnswer(model.ownUses([_use('casa', 5), _use('familia', -1)]));
      model.finishSession();
      expect(model.state.bonusUses, isNotEmpty);
      expect(
        model.state.recordedUses.map((u) => u.metadata.sessionId).toSet(),
        {model.id},
      );
    });

    test('keeps its id through a save and restore', () {
      final model = _session();
      expect(_session().id, isNot(model.id));
      expect(
        AnalyticsPracticeSessionModel.fromJson(model.toJson()).id,
        model.id,
      );
    });

    test('a session saved before ids existed takes a new one', () {
      final saved = _session().toJson()..remove('id');
      expect(AnalyticsPracticeSessionModel.fromJson(saved).id, isNotEmpty);
    });
  });
}
