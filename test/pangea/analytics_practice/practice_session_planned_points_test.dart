import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

AnalyticsPracticeTarget _target(String lemma, PracticeExerciseTypeEnum type) =>
    AnalyticsPracticeTarget(
      target: PracticeTarget(
        tokens: [
          PangeaToken(
            text: PangeaTokenText(
              content: lemma,
              offset: 0,
              length: lemma.length,
            ),
            lemma: Lemma(text: lemma, saveVocab: true, form: lemma),
            pos: 'NOUN',
            morph: const {},
          ),
        ],
        exerciseType: type,
      ),
    );

/// The start page counts the distinct words among the exercises a session
/// plans to show, not a fixed 10 (practice-exercises.instructions.md, "Start
/// page").
void main() {
  AnalyticsPracticeSessionModel session(List<AnalyticsPracticeTarget> t) =>
      AnalyticsPracticeSessionModel(
        type: ConstructTypeEnum.vocab,
        practiceTargets: t,
        userL1: 'en',
        userL2: 'es',
      );

  test('a word with two exercises counts once', () {
    final points = session([
      _target('gato', PracticeExerciseTypeEnum.lemmaMeaning),
      _target('gato', PracticeExerciseTypeEnum.lemmaAudio),
      _target('perro', PracticeExerciseTypeEnum.readAloud),
    ]).plannedPoints;

    expect(points.map((p) => p.tokens.first.lemma.text), ['gato', 'perro']);
  });

  test('the spares past the ten shown are not counted', () {
    final targets = [
      for (var i = 0; i < 15; i++)
        _target('w$i', PracticeExerciseTypeEnum.lemmaMeaning),
    ];

    expect(session(targets).plannedPoints.length, 10);
  });
}
