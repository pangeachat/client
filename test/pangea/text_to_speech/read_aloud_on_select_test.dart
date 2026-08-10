import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/text_to_speech/message_read_aloud_controller.dart';

// Reading on select: tapping a message is a deliberate request to hear it, so
// for a learner who opted into read-aloud it speaks that message. Same toggle,
// no second setting -- the same feature reached a second way.
//
// Design ("Reading on select"):
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

    // No second setting: a learner who never opted into read-aloud must not
    // start getting unrequested audio out of an ordinary message tap.
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
