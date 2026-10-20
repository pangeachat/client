import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_practice_exercise_generator.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

/// Tokenizes [sentence] on spaces, splitting a trailing "." or "," off as its
/// own token at the offset the message tokenizer would give it.
List<PangeaToken> _tokens(String sentence) {
  final tokens = <PangeaToken>[];
  var offset = 0;
  for (final raw in sentence.split(' ')) {
    var word = raw;
    String? open;
    String? punct;
    if (word.startsWith('¿') || word.startsWith('¡')) {
      open = word.substring(0, 1);
      word = word.substring(1);
    }
    if (word.isNotEmpty && '.,?!'.contains(word[word.length - 1])) {
      punct = word.substring(word.length - 1);
      word = word.substring(0, word.length - 1);
    }
    if (open != null) {
      tokens.add(_token(open, offset));
      offset += 1;
    }
    tokens.add(_token(word, offset));
    offset += word.length;
    if (punct != null) {
      tokens.add(_token(punct, offset));
      offset += 1;
    }
    offset += 1;
  }
  return tokens;
}

PangeaToken _token(String text, int offset) => PangeaToken(
  text: PangeaTokenText(content: text, offset: offset, length: text.length),
  lemma: Lemma(text: text.toLowerCase(), saveVocab: true, form: text),
  pos: 'NOUN',
  morph: const {},
);

const _sentence =
    'Ayer mi hermana compró pan fresco, queso, manzanas y leche en el mercado pequeño cerca de la plaza antigua.';

const _twoSentences =
    '¿Cuándo debemos irnos? Tenemos que estar allí para las cinco.';

ReadAloudPracticeExerciseModel _exerciseOf(String sentence, String target) =>
    ReadAloudPracticeExerciseModel(
      targetLemma: target,
      exampleTokens: _tokens(sentence),
      langCode: 'es',
      roomId: '!room',
      eventId: r'$evt',
      exampleMessage: ExampleMessageInfo(
        exampleMessage: [TextSpan(text: sentence)],
      ),
    );

ReadAloudPracticeExerciseModel _exercise(String target) =>
    _exerciseOf(_sentence, target);

String _text(ReadAloudPracticeExerciseModel e) =>
    e.exampleMessage.exampleMessage.map((s) => (s as TextSpan).text).join();

/// A read-aloud item reads at most eight words around the target
/// (practice-exercises.instructions.md, "Speaking practice").
void main() {
  test('keeps the whole sentence that holds the target, cut at its stops', () {
    final trimmed = ReadAloudPracticeExerciseGenerator.trimToSentence(
      _exerciseOf(_twoSentences, 'irnos'),
      maxWords: 8,
    );
    expect(_text(trimmed), '¿Cuándo debemos irnos?');
    expect(trimmed.referenceTokens.map((t) => t.text.content), [
      'Cuándo',
      'debemos',
      'irnos',
    ]);
    expect(trimmed.targetIndex, 2);
  });

  test('a target in the second sentence gets that sentence alone', () {
    final trimmed = ReadAloudPracticeExerciseGenerator.trimToSentence(
      _exerciseOf(_twoSentences, 'cinco'),
      maxWords: 8,
    );
    expect(_text(trimmed), 'Tenemos que estar allí para las cinco.');
    expect(trimmed.referenceTokens.length, 7);
  });

  test('a target in the middle gets a window around it, cut both sides', () {
    final trimmed = ReadAloudPracticeExerciseGenerator.trimToSentence(
      _exercise('mercado'),
      maxWords: 8,
    );
    expect(trimmed.referenceTokens.length, 8);
    // Three words before the target, four after.
    expect(trimmed.referenceTokens.map((t) => t.text.content), [
      'leche',
      'en',
      'el',
      'mercado',
      'pequeño',
      'cerca',
      'de',
      'la',
    ]);
    expect(trimmed.targetIndex, 3);
    expect(_text(trimmed), '… leche en el mercado pequeño cerca de la…');
    expect(trimmed.referenceText, 'leche en el mercado pequeño cerca de la');
  });

  test('a target near the start keeps the sentence start', () {
    final trimmed = ReadAloudPracticeExerciseGenerator.trimToSentence(
      _exercise('hermana'),
      maxWords: 8,
    );
    expect(trimmed.referenceTokens.first.text.content, 'Ayer');
    expect(trimmed.referenceTokens.length, 8);
    expect(_text(trimmed), startsWith('Ayer mi hermana'));
    expect(_text(trimmed), endsWith('…'));
  });

  test('a target near the end keeps the final stop glued to its word', () {
    final trimmed = ReadAloudPracticeExerciseGenerator.trimToSentence(
      _exercise('plaza'),
      maxWords: 8,
    );
    expect(trimmed.referenceTokens.length, 8);
    expect(trimmed.exampleTokens.last.text.content, '.');
    expect(_text(trimmed), '… el mercado pequeño cerca de la plaza antigua.');
  });

  test('a short sentence is left whole', () {
    final short = ReadAloudPracticeExerciseModel(
      targetLemma: 'gato',
      exampleTokens: _tokens('El gato come.'),
      langCode: 'es',
      exampleMessage: const ExampleMessageInfo(
        exampleMessage: [TextSpan(text: 'El gato come.')],
      ),
    );
    expect(
      identical(
        ReadAloudPracticeExerciseGenerator.trimToSentence(short, maxWords: 8),
        short,
      ),
      isTrue,
    );
  });
}
