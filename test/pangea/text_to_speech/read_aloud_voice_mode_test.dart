import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/text_to_speech/message_read_aloud_controller.dart';

// Voice mode: the learner sent a voice message, so the bot's reply to it may
// reach backend TTS rather than staying silent when the device has no
// known-good voice for the L2.
//
// Voice mode is deliberately NOT a switch on *whether* a message is read.
// TtsController gates every request on its TtsUseCase's tool setting, so a read
// still requires audioIncomingMessages either way. These tests pin the one
// thing voice mode does decide: the playback source.
//
// Design: client/.github/instructions/message-read-aloud.instructions.md

void main() {
  group('useBackendTts', () {
    test('the bot reply to a voice message may use backend TTS', () {
      expect(
        MessageReadAloudController.useBackendTts(
          voiceMode: true,
          senderIsBot: true,
        ),
        isTrue,
      );
    });

    test('outside voice mode the bot reply stays device-only', () {
      expect(
        MessageReadAloudController.useBackendTts(
          voiceMode: false,
          senderIsBot: true,
        ),
        isFalse,
      );
    });

    // A busy activity room must not turn every participant's message into a
    // paid request just because the learner spoke once.
    test('a human message in voice mode stays device-only', () {
      expect(
        MessageReadAloudController.useBackendTts(
          voiceMode: true,
          senderIsBot: false,
        ),
        isFalse,
      );
    });

    test('a human message outside voice mode stays device-only', () {
      expect(
        MessageReadAloudController.useBackendTts(
          voiceMode: false,
          senderIsBot: false,
        ),
        isFalse,
      );
    });

    test('backend is the exception, never the default', () {
      // Exactly one of the four combinations may reach backend.
      final allowed = <bool>[
        for (final voiceMode in [true, false])
          for (final senderIsBot in [true, false])
            MessageReadAloudController.useBackendTts(
              voiceMode: voiceMode,
              senderIsBot: senderIsBot,
            ),
      ].where((v) => v).length;
      expect(allowed, 1);
    });
  });
}
