import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

/// [PracticeTarget] compares its tokens by content (`listEquals`), so it has to
/// hash them by content too. It used to hash the token list directly, and a
/// plain Dart `List` hashes by identity — equal targets hashed differently,
/// which silently broke any hash-keyed use of a target (#8432).
void main() {
  PangeaToken token(String content, {int offset = 0}) => PangeaToken(
    text: PangeaTokenText.fromJson({'content': content, 'offset': offset}),
    lemma: Lemma(text: content, saveVocab: true, form: content),
    pos: 'NOUN',
    morph: const {},
  );

  PracticeTarget target(
    List<String> contents, {
    PracticeExerciseTypeEnum type = PracticeExerciseTypeEnum.wordMeaning,
    MorphFeaturesEnum? morphFeature,
  }) => PracticeTarget(
    tokens: contents.map(token).toList(),
    exerciseType: type,
    morphFeature: morphFeature,
  );

  test('equal targets built from separate tokens hash equally', () {
    expect(target(['gato']) == target(['gato']), isTrue);
    expect(target(['gato']).hashCode, target(['gato']).hashCode);
  });

  test('targets keyed into a map find each other by content', () {
    final byTarget = {
      target(['gato', 'perro']): 'exercise',
    };

    expect(byTarget[target(['gato', 'perro'])], 'exercise');
  });

  test('different tokens, types and morph features are not equal', () {
    expect(target(['gato']) == target(['perro']), isFalse);
    expect(
      target(['gato']) ==
          target(['gato'], type: PracticeExerciseTypeEnum.emoji),
      isFalse,
    );
    expect(
      target(
            ['gato'],
            type: PracticeExerciseTypeEnum.morphId,
            morphFeature: MorphFeaturesEnum.Number,
          ) ==
          target(
            ['gato'],
            type: PracticeExerciseTypeEnum.morphId,
            morphFeature: MorphFeaturesEnum.Gender,
          ),
      isFalse,
    );
  });
}
