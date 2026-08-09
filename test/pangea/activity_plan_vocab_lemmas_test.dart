import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// `ActivityPlanModel.vocabLemmas` is the single source of the lower-cased
/// target-vocab lemma set used by the message highlight and the used-vocab
/// tracker (issue #7659). Membership tests there compare against lower-cased
/// token lemmas, so this getter must lower-case and dedupe.
void main() {
  ActivityPlanModel plan(List<Vocab> vocab) => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: 'jobs',
      mode: 'Roleplay',
      objective: 'introduce yourself',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: 2,
    ),
    title: 't',
    learningObjective: 'lo',
    instructions: 'i',
    vocab: vocab,
    activityId: 'act-1',
  );

  test('lower-cases and dedupes lemmas across differing case/pos', () {
    final p = plan([
      Vocab(lemma: 'Hola', pos: 'INTJ'),
      Vocab(lemma: 'hola', pos: 'NOUN'),
      Vocab(lemma: 'Gracias', pos: 'INTJ'),
    ]);

    expect(p.vocabLemmas, {'hola', 'gracias'});
  });

  test('empty vocab yields an empty set', () {
    expect(plan(const []).vocabLemmas, isEmpty);
  });
}
