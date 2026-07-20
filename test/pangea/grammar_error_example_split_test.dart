import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_error_example_widget.dart';

/// Unit coverage for the grammar-practice cloze split (#7360): the blank must
/// land exactly on the target word — grapheme-aligned — not slide into the
/// following one. The generator now feeds this the match's own fullText, the
/// string the offset/length were measured against.
void main() {
  group('GrammarErrorExampleWidget.splitAroundBlank', () {
    test('blanks exactly the target word, not the next one', () {
      // "El gato come" — target "gato" at grapheme offset 3, length 4.
      final s = GrammarErrorExampleWidget.splitAroundBlank(
        'El gato come',
        3,
        4,
      );
      expect(s.before, 'El ');
      expect(s.after, ' come');
      expect(s.trimmedBefore, isFalse);
      expect(s.trimmedAfter, isFalse);
    });

    test('handles a target at the very start', () {
      final s = GrammarErrorExampleWidget.splitAroundBlank('gato come', 0, 4);
      expect(s.before, isEmpty);
      expect(s.after, ' come');
    });

    test('handles a target at the very end', () {
      final s = GrammarErrorExampleWidget.splitAroundBlank('come gato', 5, 4);
      expect(s.before, 'come ');
      expect(s.after, isEmpty);
    });

    test('grapheme-based: a multi-code-unit char before the target keeps the '
        'blank aligned', () {
      // The emoji is one grapheme but two UTF-16 code units; a code-unit
      // split would land mid-character. Graphemes: ['🙂',' ','g','a','t','o'].
      final s = GrammarErrorExampleWidget.splitAroundBlank('🙂 gato', 2, 4);
      expect(s.before, '🙂 ');
      expect(s.after, isEmpty);
    });
  });
}
