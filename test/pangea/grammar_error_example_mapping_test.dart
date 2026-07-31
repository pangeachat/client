import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_error_practice_generator.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_record_model.dart';

/// Coverage for #8044: the grammar-practice example must read as the message
/// the learner actually sent — every accepted writing-assistance correction
/// applied — with just the one target span blanked. The match's own `fullText`
/// only carries the corrections made up to its own step, so a learner writing
/// in their L1 and accepting suggestions one at a time saw a mostly-English
/// example.
///
/// Records are built the way the choreographer builds them, via [addRecord],
/// so the edits under test are real [ChoreoEditModel] diffs.
ChoreoRecordModel _record(String originalText, List<String> steps) {
  final record = ChoreoRecordModel(
    originalText: originalText,
    choreoSteps: [],
    openMatches: [],
  );
  for (final step in steps) {
    record.addRecord(step);
  }
  return record;
}

void main() {
  group('GrammarErrorPracticeGenerator.resolveExample', () {
    test('shows the sent text with every later correction applied, blanking '
        'only the step-0 target', () {
      // "have" -> "habe" (step 0, the target), then "hund" -> "Hund".
      final record = _record('Ich have ein hund', [
        'Ich habe ein hund',
        'Ich habe ein Hund',
      ]);

      final example = GrammarErrorPracticeGenerator.resolveExample(
        choreo: record,
        stepIndex: 0,
        matchOffset: 4,
        storedLength: 4,
        correctChoice: 'habe',
        sentText: 'Ich habe ein Hund',
        // What the old code showed: the sentence as of step 0, still carrying
        // the uncorrected "hund".
        fallbackText: 'Ich habe ein hund',
      );

      expect(example.text, 'Ich habe ein Hund');
      expect(example.offset, 4);
      expect(example.length, 4);
      expect(
        example.text.characters
            .skip(example.offset)
            .take(example.length)
            .toString(),
        'habe',
      );
    });

    test('stays aligned when the learner kept typing after the last '
        'correction', () {
      final record = _record('Ich have ein hund', ['Ich habe ein hund']);

      final example = GrammarErrorPracticeGenerator.resolveExample(
        choreo: record,
        stepIndex: 0,
        matchOffset: 4,
        storedLength: 4,
        correctChoice: 'habe',
        sentText: 'Ich habe ein hund und eine Katze',
        fallbackText: 'Ich habe ein hund',
      );

      expect(example.text, 'Ich habe ein hund und eine Katze');
      expect(example.offset, 4);
      expect(example.length, 4);
    });

    test('uses the corrected length over a stale stored length (#5655), '
        'measured against the step text', () {
      final record = _record('Yo creo que esta bien', [
        'Yo creo que están bien',
        'Yo creo que están bueno',
      ]);

      final example = GrammarErrorPracticeGenerator.resolveExample(
        choreo: record,
        stepIndex: 0,
        matchOffset: 12,
        storedLength: 4, // pre-correction "esta"
        correctChoice: 'están',
        sentText: 'Yo creo que están bueno',
        fallbackText: 'Yo creo que están bien',
      );

      expect(example.text, 'Yo creo que están bueno');
      expect(example.offset, 12);
      expect(example.length, 5);
      expect(
        example.text.characters
            .skip(example.offset)
            .take(example.length)
            .toString(),
        'están',
      );
    });

    test('a multi-code-unit grapheme before the target keeps the blank '
        'aligned', () {
      // The emoji is one grapheme but two UTF-16 code units. The walk runs in
      // code units and converts back once, so the returned offset must be the
      // grapheme one the blank renderer expects.
      final record = _record('🙂 Ich have ein hund', [
        '🙂 Ich habe ein hund',
        '🙂 Ich habe ein Hund',
      ]);

      final example = GrammarErrorPracticeGenerator.resolveExample(
        choreo: record,
        stepIndex: 0,
        matchOffset: 6,
        storedLength: 4,
        correctChoice: 'habe',
        sentText: '🙂 Ich habe ein Hund',
        fallbackText: '🙂 Ich habe ein hund',
      );

      expect(example.text, '🙂 Ich habe ein Hund');
      expect(example.offset, 6);
      expect(example.length, 4);
      expect(
        example.text.characters
            .skip(example.offset)
            .take(example.length)
            .toString(),
        'habe',
      );
    });

    test('falls back to the old base text when a later edit reworked the '
        'target span', () {
      final record = _record('Ich have ein hund', [
        'Ich habe ein hund',
        'Ich hab ein hund', // the learner edited the corrected word afterwards
      ]);

      final example = GrammarErrorPracticeGenerator.resolveExample(
        choreo: record,
        stepIndex: 0,
        matchOffset: 4,
        storedLength: 4,
        correctChoice: 'habe',
        sentText: 'Ich hab ein hund',
        fallbackText: 'Ich habe ein hund',
      );

      expect(example.text, 'Ich habe ein hund');
      expect(example.offset, 4);
      expect(example.length, 4);
    });

    test('falls back when the session carries no sent text (restored from '
        'storage before #8044)', () {
      final record = _record('Ich have ein hund', ['Ich habe ein hund']);

      final example = GrammarErrorPracticeGenerator.resolveExample(
        choreo: record,
        stepIndex: 0,
        matchOffset: 4,
        storedLength: 4,
        correctChoice: 'habe',
        sentText: null,
        fallbackText: 'Ich habe ein hund',
      );

      expect(example.text, 'Ich habe ein hund');
      expect(example.offset, 4);
      expect(example.length, 4);
    });
  });

  group('GrammarErrorPracticeGenerator.mapSpanToSentText', () {
    test('returns null when a later edit overlaps the span', () {
      final record = _record('Ich have ein hund', [
        'Ich habe ein hund',
        'Ich hab ein hund',
      ]);

      final mapped = GrammarErrorPracticeGenerator.mapSpanToSentText(
        choreo: record,
        stepIndex: 0,
        offset: 4,
        length: 4,
        sentText: 'Ich hab ein hund',
      );

      expect(mapped, isNull);
    });

    test('returns null when the span runs past the step text', () {
      final record = _record('Ich have ein hund', ['Ich habe ein hund']);

      final mapped = GrammarErrorPracticeGenerator.mapSpanToSentText(
        choreo: record,
        stepIndex: 0,
        offset: 14,
        length: 20,
        sentText: 'Ich habe ein hund',
      );

      expect(mapped, isNull);
    });
  });

  group('GrammarErrorPracticeGenerator.originalErrorSpan', () {
    test('recovers the learner\'s own word for a same-length correction', () {
      final record = _record('Ich have ein hund', ['Ich habe ein hund']);

      expect(
        GrammarErrorPracticeGenerator.originalErrorSpan(
          choreo: record,
          stepIndex: 0,
          matchOffset: 4,
          correctChoice: 'habe',
        ),
        'have',
      );
    });

    test('recovers it when the correction changed the span length', () {
      final record = _record('Yo creo que esta bien', [
        'Yo creo que están bien',
      ]);

      expect(
        GrammarErrorPracticeGenerator.originalErrorSpan(
          choreo: record,
          stepIndex: 0,
          matchOffset: 12,
          correctChoice: 'están',
        ),
        'esta',
      );
    });

    test('returns null when the learner typed elsewhere in the same step, so '
        'the diff covers more than the correction', () {
      final record = _record('Ich have ein hund', ['Ich habe ein hund heute']);

      expect(
        GrammarErrorPracticeGenerator.originalErrorSpan(
          choreo: record,
          stepIndex: 0,
          matchOffset: 4,
          correctChoice: 'habe',
        ),
        isNull,
      );
    });

    test('returns null when the corrected span is not at the match offset', () {
      final record = _record('Ich have ein hund', ['Ich habe ein hund']);

      expect(
        GrammarErrorPracticeGenerator.originalErrorSpan(
          choreo: record,
          stepIndex: 0,
          matchOffset: 9,
          correctChoice: 'habe',
        ),
        isNull,
      );
    });
  });
}
