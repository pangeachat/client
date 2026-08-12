import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/toolbar/practice_exercises/emoji_practice_exercise_generator.dart';

void main() {
  group('pickEmojiChoice', () {
    test('picks the first unused candidate', () {
      expect(pickEmojiChoice(candidates: ['🍎', '🍏'], used: []), '🍎');
      expect(pickEmojiChoice(candidates: ['🍎', '🍏'], used: ['🍎']), '🍏');
    });

    test('skips flagged content when an alternative exists', () {
      // The regenerated row kept the flagged emoji (minimal-edit regen) —
      // the rebuilt exercise must not re-display what the user reported.
      expect(
        pickEmojiChoice(candidates: ['🍒', '🍎'], used: [], avoid: '🍒'),
        '🍎',
      );
    });

    test('avoidance composes with uniqueness', () {
      expect(
        pickEmojiChoice(
          candidates: ['🍇', '🍒', '🍎'],
          used: ['🍒'],
          avoid: '🍇',
        ),
        '🍎',
      );
    });

    test('falls back to the flagged content when it is the only option', () {
      // A row whose sole unused emoji is the flagged one is served as-is
      // rather than failing the whole exercise.
      expect(pickEmojiChoice(candidates: ['🍇'], used: [], avoid: '🍇'), '🍇');
      expect(
        pickEmojiChoice(candidates: ['🍒', '🍇'], used: ['🍒'], avoid: '🍇'),
        '🍇',
      );
    });

    test('throws when every candidate is used', () {
      expect(
        () => pickEmojiChoice(candidates: ['🍎'], used: ['🍎']),
        throwsStateError,
      );
      expect(() => pickEmojiChoice(candidates: [], used: []), throwsStateError);
    });
  });
}
