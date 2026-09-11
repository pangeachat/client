import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_choice_tap.dart';

void main() {
  group('PracticeChoiceTapResolver', () {
    test('a choice does nothing until a blank is chosen', () {
      // Slot-first: the message is the first move in every mode (#6259).
      expect(
        PracticeChoiceTapResolver.resolve(
          hasSelectedSlot: false,
          isAudioChoice: false,
          isSelectedChoice: false,
        ),
        PracticeChoiceTap.ignore,
      );
      expect(
        PracticeChoiceTapResolver.resolve(
          hasSelectedSlot: false,
          isAudioChoice: true,
          isSelectedChoice: true,
        ),
        PracticeChoiceTap.ignore,
      );
    });

    test('a readable choice answers on the first tap', () {
      expect(
        PracticeChoiceTapResolver.resolve(
          hasSelectedSlot: true,
          isAudioChoice: false,
          isSelectedChoice: false,
        ),
        PracticeChoiceTap.answer,
      );
    });

    test('an audio choice plays first, then answers on a second tap', () {
      expect(
        PracticeChoiceTapResolver.resolve(
          hasSelectedSlot: true,
          isAudioChoice: true,
          isSelectedChoice: false,
        ),
        PracticeChoiceTap.preview,
      );
      expect(
        PracticeChoiceTapResolver.resolve(
          hasSelectedSlot: true,
          isAudioChoice: true,
          isSelectedChoice: true,
        ),
        PracticeChoiceTap.answer,
      );
    });
  });
}
