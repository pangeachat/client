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

PangeaToken _token(String lemma) => PangeaToken(
  text: PangeaTokenText(content: lemma, offset: 0, length: lemma.length),
  lemma: Lemma(text: lemma, saveVocab: true, form: lemma),
  pos: 'NOUN',
  morph: const {},
);

AnalyticsPracticeTarget _ranked(String lemma) => AnalyticsPracticeTarget(
  target: PracticeTarget(
    tokens: [_token(lemma)],
    exerciseType: PracticeExerciseTypeEnum.lemmaMeaning,
  ),
);

PracticeWord _word(
  String lemma, [
  Set<LearningSkillsEnum> skills = PracticeSkillsStore.vocabSkills,
]) => PracticeWord(token: _token(lemma), skills: skills);

AnalyticsPracticeSessionModel _session(
  List<PracticeWord> words,
  Set<LearningSkillsEnum> skills,
) => AnalyticsPracticeSessionModel.vocab(
  words: words,
  skills: skills,
  userL1: 'en',
  userL2: 'es',
);

List<String> _lemmas(AnalyticsPracticeSessionModel session) => [
  for (final point in session.plannedPoints) point.tokens.first.lemma.text,
];

Map<String, int> _types(AnalyticsPracticeSessionModel session) {
  final counts = <String, int>{};
  for (final t in session.practiceTargets) {
    final name = t.target.exerciseType.name;
    counts[name] = (counts[name] ?? 0) + 1;
  }
  return counts;
}

/// A vocab session picks its words once; the start page's chips only decide
/// which exercise each gets (practice-exercises.instructions.md, "Start
/// page").
void main() {
  group('rankVocabWords', () {
    test('the meaning and listening rankings take turns, each word once', () {
      final words = AnalyticsPracticeSessionRepo.rankVocabWords(
        [_ranked('a'), _ranked('b'), _ranked('c')],
        [_ranked('b'), _ranked('d')],
        skillsOf: (_) => PracticeSkillsStore.vocabSkills,
        total: 15,
      );
      expect([for (final w in words) w.token.lemma.text], ['a', 'b', 'd', 'c']);
    });

    test('stops at the session size', () {
      final words = AnalyticsPracticeSessionRepo.rankVocabWords(
        [for (var i = 0; i < 20; i++) _ranked('m$i')],
        [for (var i = 0; i < 20; i++) _ranked('l$i')],
        skillsOf: (_) => PracticeSkillsStore.vocabSkills,
        total: 15,
      );
      expect(words.length, 15);
    });
  });

  group('dealing', () {
    final words = [for (var i = 0; i < 15; i++) _word('w$i')];

    test('every word gets one exercise and the types come out even', () {
      final session = _session(words, PracticeSkillsStore.vocabSkills);

      expect(session.practiceTargets.length, 15);
      expect(_types(session), {
        'lemmaAudio': 5,
        'readAloud': 5,
        'lemmaMeaning': 5,
      });
      expect(session.plannedPoints.length, 10);
    });

    test('the words stay the same whatever the chips', () {
      final all = _session(words, PracticeSkillsStore.vocabSkills);
      for (final skills in [
        {LearningSkillsEnum.reading},
        {LearningSkillsEnum.hearing, LearningSkillsEnum.speaking},
        {LearningSkillsEnum.speaking},
      ]) {
        expect(_lemmas(all.withSkills(skills)), _lemmas(all));
      }
      expect(_types(all.withSkills({LearningSkillsEnum.speaking})), {
        'readAloud': 15,
      });
    });

    test('a word left with no exercise drops out and no spare replaces it', () {
      final mixed = [
        _word('meaningOnly', {LearningSkillsEnum.reading}),
        ...words.skip(1),
      ];
      final session = _session(mixed, {LearningSkillsEnum.hearing});

      expect(_lemmas(session), [for (var i = 1; i < 10; i++) 'w$i']);
      expect(session.practiceTargets.length, 14);
    });

    test('a type no planned word can take is unavailable', () {
      final session = _session([
        for (var i = 0; i < 10; i++) _word('w$i', {LearningSkillsEnum.reading}),
        _word('spare'),
      ], PracticeSkillsStore.vocabSkills);

      expect(session.availableSkills, {LearningSkillsEnum.reading});
      expect(session.skills, {LearningSkillsEnum.reading});
    });

    test('chips none of the words can take fall back to what they can', () {
      final session = _session(
        [
          _word('a', {LearningSkillsEnum.reading}),
        ],
        {LearningSkillsEnum.speaking},
      );

      expect(session.skills, {LearningSkillsEnum.reading});
      expect(_lemmas(session), ['a']);
    });
  });
}
