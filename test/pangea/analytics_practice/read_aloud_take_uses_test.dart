import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

PangeaToken _token(String text, int offset, {bool saveVocab = true}) =>
    PangeaToken(
      text: PangeaTokenText(content: text, offset: offset, length: text.length),
      lemma: Lemma(text: text.toLowerCase(), saveVocab: saveVocab, form: text),
      pos: 'NOUN',
      morph: const {},
    );

/// "El gato come." with "gato" as the target; "El" is kept out of vocabulary
/// the way the tokenizer keeps a determiner out.
ReadAloudPracticeExerciseModel _exercise() => ReadAloudPracticeExerciseModel(
  targetLemma: 'gato',
  exampleTokens: [
    _token('El', 0, saveVocab: false),
    _token('gato', 3),
    _token('come', 8),
    _token('.', 12),
  ],
  langCode: 'es',
  exampleMessage: const ExampleMessageInfo(
    exampleMessage: [TextSpan(text: 'El gato come.')],
  ),
);

/// What one recorded take earns. See practice-exercises.instructions.md,
/// "Speaking practice", What counts.
void main() {
  test('the target earns the read-aloud use; every other heard vocabulary '
      'word earns the voice-message word use', () {
    final uses = _exercise().takeUses(
      targetHeard: true,
      heard: [true, true, true],
    );
    expect(uses.map((u) => u.useType), [
      ConstructUseTypeEnum.corRA,
      ConstructUseTypeEnum.pvm,
    ]);
    expect(uses.map((u) => u.lemma), ['gato', 'come']);
    expect(
      uses.every((u) => u.constructType == ConstructTypeEnum.vocab),
      isTrue,
    );
    expect(
      uses.fold<int>(0, (sum, u) => sum + u.xp),
      ConstructUseTypeEnum.corRA.pointValue +
          ConstructUseTypeEnum.pvm.pointValue,
    );
  });

  test('a word not heard earns nothing and is never a miss', () {
    final uses = _exercise().takeUses(
      targetHeard: true,
      heard: [true, true, false],
    );
    expect(uses.map((u) => u.useType), [ConstructUseTypeEnum.corRA]);
  });

  test('a missed target is the one miss; the heard words still count', () {
    final uses = _exercise().takeUses(
      targetHeard: false,
      heard: [true, false, true],
    );
    expect(uses.map((u) => u.useType), [
      ConstructUseTypeEnum.incRA,
      ConstructUseTypeEnum.pvm,
    ]);
    expect(uses.first.xp, 0);
    expect(uses.where((u) => u.xp == 0).length, 1);
  });
}
