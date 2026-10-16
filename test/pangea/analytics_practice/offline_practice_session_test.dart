import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

AnalyticsPracticeSessionModel _session({required bool offline}) =>
    AnalyticsPracticeSessionModel(
      type: ConstructTypeEnum.vocab,
      practiceTargets: [
        for (final word in ['gato', 'perro'])
          AnalyticsPracticeTarget(
            target: PracticeTarget(
              tokens: [
                PangeaToken(
                  text: PangeaTokenText.fromJson({
                    'content': word,
                    'offset': 0,
                  }),
                  lemma: Lemma(text: word, saveVocab: true, form: word),
                  pos: 'NOUN',
                  morph: const {},
                ),
              ],
              exerciseType: PracticeExerciseTypeEnum.lemmaMeaning,
            ),
          ),
      ],
      userL1: 'en',
      userL2: 'es',
      offline: offline,
    );

/// #9513 — a session started offline stays offline, and every exercise it
/// asks for is built from what the device has.
void main() {
  test('every exercise an offline session asks for is built offline', () {
    final requests = _session(offline: true).exerciseRequests;
    expect(requests, hasLength(2));
    expect(requests.every((request) => request.offline), isTrue);

    expect(
      _session(offline: false).exerciseRequests.any((r) => r.offline),
      isFalse,
    );
  });

  test('the offline mode survives a round trip through JSON', () {
    for (final offline in [true, false]) {
      final restored = AnalyticsPracticeSessionModel.fromJson(
        _session(offline: offline).toJson(),
      );
      expect(restored.offline, offline);
    }
  });

  test('the offline mode never reaches the request sent to the server', () {
    final request = _session(offline: true).exerciseRequests.first;
    expect(request.toJson().values, isNot(contains(true)));
  });
}
