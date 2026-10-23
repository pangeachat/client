import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_repo.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_skills_store.dart';
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
      listening: 5,
      readAloud: 5,
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
    final split = AnalyticsPracticeSessionRepo.alternateListeningAndReadAloud(
      [_listening('a'), _listening('b'), _listening('c')],
      listening: 5,
      readAloud: 5,
    );
    expect(_shape(split), ['lemmaAudio:a', 'lemmaAudio:c', 'readAloud:b']);
  });

  test('one word is a listening item and nothing else', () {
    final split = AnalyticsPracticeSessionRepo.alternateListeningAndReadAloud(
      [_listening('solo')],
      listening: 5,
      readAloud: 5,
    );
    expect(_shape(split), ['lemmaAudio:solo']);
  });

  test('an empty pool yields nothing', () {
    expect(
      AnalyticsPracticeSessionRepo.alternateListeningAndReadAloud(
        const [],
        listening: 5,
        readAloud: 5,
      ),
      isEmpty,
    );
  });

  test('with listening off, the pool goes to read-aloud', () {
    final split = AnalyticsPracticeSessionRepo.alternateListeningAndReadAloud(
      [_listening('a'), _listening('b')],
      listening: 0,
      readAloud: 5,
    );
    expect(_shape(split), ['readAloud:a', 'readAloud:b']);
  });

  /// The start page's chips set which exercise types a vocab session has,
  /// an even share each (practice-exercises.instructions.md, "Start page").
  group('splitVocabTargets', () {
    final pool = [for (var i = 1; i <= 20; i++) _listening('e$i')];
    final meanings = [for (var i = 1; i <= 20; i++) _meaning('m$i')];

    Map<String, int> counts(Set<LearningSkillsEnum> skills) {
      final split = AnalyticsPracticeSessionRepo.splitVocabTargets(
        exampleTargets: pool,
        meaningTargets: meanings,
        skills: skills,
        total: 15,
      );
      final byType = <String, int>{};
      for (final t in split) {
        final name = t.target.exerciseType.name;
        byType[name] = (byType[name] ?? 0) + 1;
      }
      return byType;
    }

    test('all three types take a third each', () {
      expect(counts(PracticeSkillsStore.vocabSkills), {
        'lemmaAudio': 5,
        'readAloud': 5,
        'lemmaMeaning': 5,
      });
    });

    test('without reading, listening and speaking fill the session', () {
      expect(
        counts({LearningSkillsEnum.hearing, LearningSkillsEnum.speaking}),
        {'lemmaAudio': 8, 'readAloud': 7},
      );
    });

    test('one type fills the session alone', () {
      expect(counts({LearningSkillsEnum.speaking}), {'readAloud': 15});
      expect(counts({LearningSkillsEnum.reading}), {'lemmaMeaning': 15});
    });

    test('meaning makes up what a small pool cannot', () {
      final split = AnalyticsPracticeSessionRepo.splitVocabTargets(
        exampleTargets: pool.take(2).toList(),
        meaningTargets: meanings,
        skills: {LearningSkillsEnum.reading, LearningSkillsEnum.speaking},
        total: 15,
      );
      expect(split.length, 15);
      expect(
        split.where((t) => t.target.exerciseType.name == 'readAloud').length,
        2,
      );
    });
  });
}

AnalyticsPracticeTarget _meaning(String lemma) => AnalyticsPracticeTarget(
  target: PracticeTarget(
    tokens: _listening(lemma).target.tokens,
    exerciseType: PracticeExerciseTypeEnum.lemmaMeaning,
  ),
);
