import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_match.dart';

/// The read-aloud judge: which words of the sentence were heard, in order.
/// See practice-exercises.instructions.md, "Speaking practice".
void main() {
  group('normalizeSpokenWord', () {
    test('folds case and strips punctuation glued to the edges', () {
      expect(normalizeSpokenWord('Gato.'), 'gato');
      expect(normalizeSpokenWord('¿Qué?'), 'qué');
      expect(normalizeSpokenWord('"hola",'), 'hola');
    });

    test('keeps punctuation inside a word', () {
      expect(normalizeSpokenWord("l'école"), "l'école");
    });

    test('a punctuation-only token is not a spoken word', () {
      expect(isSpokenWord('...'), isFalse);
      expect(isSpokenWord('¿'), isFalse);
      expect(isSpokenWord('42'), isTrue);
    });
  });

  group('spokenWords', () {
    test('splits a transcript into normalized words', () {
      expect(spokenWords('  El gato,  come. '), ['el', 'gato', 'come']);
      expect(spokenWords(''), isEmpty);
    });
  });

  group('readAloudHeard', () {
    test('hears every word of a full read', () {
      expect(readAloudHeard(['El', 'gato', 'come'], ['el', 'gato', 'come']), [
        true,
        true,
        true,
      ]);
    });

    test('only counts a word in its place', () {
      expect(
        readAloudHeard(['el', 'gato', 'come'], ['gato', 'el', 'come']),
        anyOf(equals([true, false, true]), equals([false, true, true])),
      );
    });

    test('a missed word stays unheard while the rest are heard', () {
      expect(
        readAloudHeard(['el', 'gato', 'negro', 'come'], ['el', 'gato', 'come']),
        [true, true, false, true],
      );
    });

    test('a repeated word is matched once per occurrence', () {
      expect(readAloudHeard(['no', 'no', 'no'], ['no']), [true, false, false]);
      expect(readAloudHeard(['no', 'no'], ['no', 'no', 'no']), [true, true]);
    });

    test('nothing heard leaves every word unheard', () {
      expect(readAloudHeard(['el', 'gato'], []), [false, false]);
    });

    test('punctuation on either side never blocks a match', () {
      expect(readAloudHeard(['Hola,', 'mundo!'], ['hola', 'Mundo.']), [
        true,
        true,
      ]);
    });
  });
}
