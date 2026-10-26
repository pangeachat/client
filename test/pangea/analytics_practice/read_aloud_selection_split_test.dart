import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_repo.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

AnalyticsPracticeTarget _listening(String lemma) => AnalyticsPracticeTarget(
  target: PracticeTarget(
    tokens: [
      PangeaToken(
        text: PangeaTokenText(content: lemma, offset: 0, length: lemma.length),
        lemma: Lemma(text: lemma, saveVocab: true, form: lemma),
        pos: 'NOUN',
        morph: const {},
      ),
    ],
    exerciseType: PracticeExerciseTypeEnum.lemmaAudio,
  ),
);

List<String> _shape(List<AnalyticsPracticeTarget> targets) => [
  for (final t in targets)
    '${t.target.exerciseType.name}:${t.target.tokens.first.lemma.text}',
];

/// Listening and read-aloud share the one pool of example-bearing words,
/// taking turns down its priority order, so a small pool is split rather
/// than spent on listening first (practice-exercises.instructions.md,
/// "Speaking practice").
void main() {
  test('a large pool gives each its full share, alternating', () {
    final pool = [for (var i = 1; i <= 12; i++) _listening('w$i')];
    final split = AnalyticsPracticeSessionRepo.alternateListeningAndReadAloud(
      pool,
      each: 5,
    );
    expect(_shape(split), [
      'lemmaAudio:w1',
      'lemmaAudio:w3',
      'lemmaAudio:w5',
      'lemmaAudio:w7',
      'lemmaAudio:w9',
      'readAloud:w2',
      'readAloud:w4',
      'readAloud:w6',
      'readAloud:w8',
      'readAloud:w10',
    ]);
  });

  test('a small pool is shared, listening first', () {
    final split = AnalyticsPracticeSessionRepo.alternateListeningAndReadAloud([
      _listening('a'),
      _listening('b'),
      _listening('c'),
    ], each: 5);
    expect(_shape(split), ['lemmaAudio:a', 'lemmaAudio:c', 'readAloud:b']);
  });

  test('one word is a listening item and nothing else', () {
    final split = AnalyticsPracticeSessionRepo.alternateListeningAndReadAloud([
      _listening('solo'),
    ], each: 5);
    expect(_shape(split), ['lemmaAudio:solo']);
  });

  test('an empty pool yields nothing', () {
    expect(
      AnalyticsPracticeSessionRepo.alternateListeningAndReadAloud(
        const [],
        each: 5,
      ),
      isEmpty,
    );
  });
}
