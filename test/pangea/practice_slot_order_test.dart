import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_slot_order.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

/// Practice opens on the first unanswered blank and moves on by itself after
/// each right answer (#6259). "Next" means next in the message as it is read,
/// wrapping round to any blank the learner skipped.
void main() {
  PangeaToken token(String content, int offset) => PangeaToken(
    text: PangeaTokenText.fromJson({'content': content, 'offset': offset}),
    lemma: Lemma(text: content, saveVocab: true, form: content),
    pos: 'NOUN',
    morph: const {},
  );

  group('nextOpen', () {
    const words = ['porque', 'tengo', 'pasaporte', 'solo'];

    test('with nothing selected, lands on the first open blank', () {
      expect(PracticeSlotOrder.nextOpen(words, (w) => w == 'porque'), 'tengo');
    });

    test('moves on to the next open blank after the one just answered', () {
      final done = {'porque', 'tengo'};
      expect(
        PracticeSlotOrder.nextOpen(words, done.contains, after: 'tengo'),
        'pasaporte',
      );
    });

    test('skips blanks that are already answered', () {
      final done = {'tengo', 'pasaporte'};
      expect(
        PracticeSlotOrder.nextOpen(words, done.contains, after: 'tengo'),
        'solo',
      );
    });

    test('wraps round to a blank the learner skipped', () {
      // Learner jumped ahead to the last word; the first is still open.
      final done = {'tengo', 'pasaporte', 'solo'};
      expect(
        PracticeSlotOrder.nextOpen(words, done.contains, after: 'solo'),
        'porque',
      );
    });

    test('is null once every blank is answered', () {
      expect(
        PracticeSlotOrder.nextOpen(words, (_) => true, after: 'tengo'),
        isNull,
      );
    });

    test('starts from the beginning if the current blank is unknown', () {
      expect(
        PracticeSlotOrder.nextOpen(words, (_) => false, after: 'gato'),
        'porque',
      );
    });
  });

  test('a match target is walked in reading order, not selection order', () {
    // Selection shuffles a target's tokens.
    final target = PracticeTarget(
      tokens: [token('solo', 27), token('porque', 0), token('tengo', 10)],
      exerciseType: PracticeExerciseTypeEnum.wordMeaning,
    );

    expect(
      PracticeSlotOrder.tokensInReadingOrder(target).map((t) => t.text.content),
      ['porque', 'tengo', 'solo'],
    );
  });

  test('grammar targets follow their words, keeping one word\'s features '
      'in selection order', () {
    final tengo = token('tengo', 10);
    final porque = token('porque', 0);
    PracticeTarget grammar(PangeaToken t, MorphFeaturesEnum feature) =>
        PracticeTarget(
          tokens: [t],
          exerciseType: PracticeExerciseTypeEnum.morphId,
          morphFeature: feature,
        );

    final ordered = PracticeSlotOrder.targetsInReadingOrder([
      grammar(tengo, MorphFeaturesEnum.Mood),
      grammar(porque, MorphFeaturesEnum.Pos),
      grammar(tengo, MorphFeaturesEnum.Aspect),
    ]);

    expect(ordered.map((t) => (t.tokens.first.text.content, t.morphFeature)), [
      ('porque', MorphFeaturesEnum.Pos),
      ('tengo', MorphFeaturesEnum.Mood),
      ('tengo', MorphFeaturesEnum.Aspect),
    ]);
  });
}
