import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/text_to_speech/message_read_aloud_controller.dart';

// Reading on click: tapping a message is a deliberate request to hear it, so
// it speaks that message -- own messages included -- behind the "On message
// click" toggle (#8264).
//
// Design ("Reading on click"):
// client/.github/instructions/message-read-aloud.instructions.md

void main() {
  group('readsOnSelect', () {
    test('a plain tap on a message with the setting on reads it', () {
      expect(
        MessageReadAloudController.readsOnSelect(
          settingEnabled: true,
          isTutorial: false,
          tokenSelected: false,
        ),
        isTrue,
      );
    });

    // A learner who turned the click toggle off must not get audio out of an
    // ordinary message tap.
    test('the setting off reads nothing on select', () {
      expect(
        MessageReadAloudController.readsOnSelect(
          settingEnabled: false,
          isTutorial: false,
          tokenSelected: false,
        ),
        isFalse,
      );
    });

    // The tutorial opens the toolbar on the learner's behalf and speaks its own
    // instruction over it; message audio would talk across it.
    test('a tutorial-driven selection stays silent', () {
      expect(
        MessageReadAloudController.readsOnSelect(
          settingEnabled: true,
          isTutorial: true,
          tokenSelected: false,
        ),
        isFalse,
      );
    });

    // Tapping a word plays that word. The more specific request wins, and both
    // firing would have the two utterances cut each other off.
    test('tapping a token reads the word, not the message', () {
      expect(
        MessageReadAloudController.readsOnSelect(
          settingEnabled: true,
          isTutorial: false,
          tokenSelected: true,
        ),
        isFalse,
      );
    });
  });
}
