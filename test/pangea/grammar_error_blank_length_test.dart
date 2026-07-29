import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_error_practice_generator.dart';

void main() {
  group('GrammarErrorPracticeGenerator.targetBlankLength (#7360)', () {
    test('uses the corrected-span length when the stored length is stale '
        '(pre-2026-02-25 record), covering the whole target word', () {
      // fullText is the corrected sentence; the stored length (11) is the
      // pre-correction span "¿Dónde está" — one grapheme short of "¿Dónde están".
      final length = GrammarErrorPracticeGenerator.targetBlankLength(
        baseText: '¿Dónde están las fiesta? Mis amigos se gustan ir.',
        offset: 0,
        correctChoice: '¿Dónde están',
        storedLength: 11,
      );
      expect(length, 12); // grapheme length of "¿Dónde están"
    });

    test(
      'agrees with an already-consistent stored length (post-fix record)',
      () {
        final length = GrammarErrorPracticeGenerator.targetBlankLength(
          baseText: '¿Dónde están las fiesta? Mis amigos se gustan ir.',
          offset: 0,
          correctChoice: '¿Dónde están',
          storedLength: 12,
        );
        expect(length, 12);
      },
    );

    test('handles a target span that does not start at offset 0', () {
      // "Yo creo que " is 12 graphemes; the target "están" starts at 12.
      final length = GrammarErrorPracticeGenerator.targetBlankLength(
        baseText: 'Yo creo que están bien',
        offset: 12,
        correctChoice: 'están',
        storedLength: 4, // stale "esta"
      );
      expect(length, 5); // "están"
    });

    test('falls back to the stored length when the corrected span is not '
        'present at offset (malformed / ignored-form record)', () {
      // Here fullText still holds the erroneous form, so bestChoice is absent.
      final length = GrammarErrorPracticeGenerator.targetBlankLength(
        baseText: '¿Dónde está las fiesta?',
        offset: 0,
        correctChoice: '¿Dónde están',
        storedLength: 11,
      );
      expect(length, 11); // unchanged — blanks the error span as before
    });

    test('counts by grapheme, not UTF-16 code unit, for accented targets', () {
      // "café" is 4 graphemes even though "é" may be multi-code-unit.
      final length = GrammarErrorPracticeGenerator.targetBlankLength(
        baseText: 'un café con leche',
        offset: 3,
        correctChoice: 'café',
        storedLength: 3,
      );
      expect(length, 4);
    });
  });
}
