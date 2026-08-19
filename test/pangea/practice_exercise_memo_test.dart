import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_form.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_exercise_memo.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/match_practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

/// [PracticeExerciseMemo] replaced `PracticeRepo`'s storage-backed exercise
/// cache (#8432), which could never hit: it keyed entries on the request's
/// `hashCode`, and a `PracticeTarget` hashed its tokens by list identity, so a
/// target rebuilt from the selection cache — which is how every re-open of the
/// toolbar gets its targets — produced a different key for the same word.
///
/// What matters here is the property that made the old key useless: a target
/// that is equal by content, not by identity, must find the exercise already
/// generated for it. The memo keys on [PracticeTarget.storageKey], the same key
/// practice records use.
void main() {
  PangeaToken token(String content, {int offset = 0}) => PangeaToken(
    text: PangeaTokenText.fromJson({'content': content, 'offset': offset}),
    lemma: Lemma(text: content, saveVocab: true, form: content),
    pos: 'NOUN',
    morph: const {},
  );

  PracticeTarget target(
    String content, {
    PracticeExerciseTypeEnum type = PracticeExerciseTypeEnum.wordMeaning,
    MorphFeaturesEnum? morphFeature,
  }) => PracticeTarget(
    tokens: [token(content)],
    exerciseType: type,
    morphFeature: morphFeature,
  );

  PracticeExerciseModel exercise(String content) =>
      LemmaMeaningPracticeExerciseModel(
        langCode: 'es',
        tokens: [token(content)],
        matchContent: MatchPracticeExercise(
          matchInfo: {
            ConstructForm(
              form: content,
              cId: ConstructIdentifier(
                lemma: content,
                type: ConstructTypeEnum.vocab,
                category: 'NOUN',
              ),
            ): [
              '$content-meaning',
            ],
          },
        ),
      );

  test('an equal target rebuilt from scratch reads back its exercise', () {
    final memo = PracticeExerciseMemo();
    final written = exercise('gato');
    memo.write(target('gato'), written);

    // A separate instance, as the selection cache hands back after a re-parse.
    expect(memo.read(target('gato')), same(written));
  });

  test('a target with no exercise reads back null', () {
    final memo = PracticeExerciseMemo();
    memo.write(target('gato'), exercise('gato'));

    expect(memo.read(target('perro')), isNull);
  });

  test('exercise type and morph feature are part of the key', () {
    final memo = PracticeExerciseMemo();
    final wordMeaning = exercise('gato');
    memo.write(target('gato'), wordMeaning);

    expect(
      memo.read(target('gato', type: PracticeExerciseTypeEnum.emoji)),
      isNull,
    );
    expect(
      memo.read(
        target(
          'gato',
          type: PracticeExerciseTypeEnum.morphId,
          morphFeature: MorphFeaturesEnum.Number,
        ),
      ),
      isNull,
    );
    expect(memo.read(target('gato')), same(wordMeaning));
  });

  test('remove drops the exercise so the next read regenerates', () {
    final memo = PracticeExerciseMemo();
    memo.write(target('gato'), exercise('gato'));

    memo.remove(target('gato'));

    expect(memo.read(target('gato')), isNull);
  });

  test('a rewritten target serves the newer exercise', () {
    final memo = PracticeExerciseMemo();
    memo.write(target('gato'), exercise('gato'));
    final corrected = exercise('gato');
    memo.write(target('gato'), corrected);

    expect(memo.read(target('gato')), same(corrected));
  });
}
