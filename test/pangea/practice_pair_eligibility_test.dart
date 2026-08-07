import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_exercise_feedback_dialog.dart';

void main() {
  group('practicePairEligibility', () {
    test('a pair with server-generated content is flaggable', () {
      expect(
        practicePairEligibility(
          isEmojiExercise: true,
          choiceContent: '🍇',
          userSetEmoji: null,
          alreadyMatchedCorrectly: false,
        ),
        PracticePairEligibility.flaggable,
      );
    });

    test('a user-set emoji is not flaggable in the emoji exercise', () {
      expect(
        practicePairEligibility(
          isEmojiExercise: true,
          choiceContent: '🍎',
          userSetEmoji: '🍎',
          alreadyMatchedCorrectly: false,
        ),
        PracticePairEligibility.userSetEmoji,
      );
    });

    test('a user-set emoji on a different choice does not block flagging', () {
      expect(
        practicePairEligibility(
          isEmojiExercise: true,
          choiceContent: '🍇',
          userSetEmoji: '🍎',
          alreadyMatchedCorrectly: false,
        ),
        PracticePairEligibility.flaggable,
      );
    });

    test('user-set emoji is ignored outside the emoji exercise', () {
      // The meaning exercise's content always comes from the server, even
      // when the user has set their own emoji for the same lemma.
      expect(
        practicePairEligibility(
          isEmojiExercise: false,
          choiceContent: '🍎',
          userSetEmoji: '🍎',
          alreadyMatchedCorrectly: false,
        ),
        PracticePairEligibility.flaggable,
      );
    });

    test('a correctly matched pair is not flaggable', () {
      expect(
        practicePairEligibility(
          isEmojiExercise: false,
          choiceContent: 'apple',
          userSetEmoji: null,
          alreadyMatchedCorrectly: true,
        ),
        PracticePairEligibility.alreadyMatched,
      );
    });

    test('user-set emoji takes precedence over already-matched', () {
      // Both apply; the user-set hint is the more actionable message.
      expect(
        practicePairEligibility(
          isEmojiExercise: true,
          choiceContent: '🍎',
          userSetEmoji: '🍎',
          alreadyMatchedCorrectly: true,
        ),
        PracticePairEligibility.userSetEmoji,
      );
    });
  });
}
