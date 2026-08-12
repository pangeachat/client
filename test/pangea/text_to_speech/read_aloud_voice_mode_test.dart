import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/text_to_speech/message_read_aloud_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';

// Voice mode: the learner sent a voice message, so the bot's reply to it is
// read aloud whether or not audioOnNewMessage is on, and may reach backend
// TTS rather than staying silent when the device has no known-good L2 voice.
//
// Both properties belonged to the bot-generated audio this replaces: it always
// played, and it always cost a paid request. The point of the change is to keep
// the behaviour while routing device-first and restoring the full toolbar.
//
// Design: client/.github/instructions/message-read-aloud.instructions.md

void main() {
  group('isVoiceReply', () {
    test('the bot answering a voice message is a voice reply', () {
      expect(
        MessageReadAloudController.isVoiceReply(
          voiceMode: true,
          senderIsBot: true,
        ),
        isTrue,
      );
    });

    test('outside voice mode the bot is just another sender', () {
      expect(
        MessageReadAloudController.isVoiceReply(
          voiceMode: false,
          senderIsBot: true,
        ),
        isFalse,
      );
    });

    // One voice message must not start speaking every participant in a busy
    // activity room -- the single waiting slot would silently drop most of them.
    test('another participant in voice mode is not a voice reply', () {
      expect(
        MessageReadAloudController.isVoiceReply(
          voiceMode: true,
          senderIsBot: false,
        ),
        isFalse,
      );
    });
  });

  group('qualifies', () {
    test('the setting alone reads any sender', () {
      expect(
        MessageReadAloudController.qualifies(
          settingEnabled: true,
          voiceReply: false,
        ),
        isTrue,
      );
    });

    // The regression this guards: with audioOnNewMessage off, a voice message
    // would otherwise get a silent reply, where the bot used to speak it
    // automatically.
    test('a voice reply is read even with the setting off', () {
      expect(
        MessageReadAloudController.qualifies(
          settingEnabled: false,
          voiceReply: true,
        ),
        isTrue,
      );
    });

    test('setting off and not a voice reply reads nothing', () {
      expect(
        MessageReadAloudController.qualifies(
          settingEnabled: false,
          voiceReply: false,
        ),
        isFalse,
      );
    });
  });

  group('TtsUseCase gating', () {
    test('voiceReply is ungated', () {
      expect(TtsUseCase.voiceReply.toolSetting, isNull);
    });

    test('every other use case is gated by its own toggle', () {
      expect(TtsUseCase.words.toolSetting, ToolSetting.audioWords);
      expect(TtsUseCase.choices.toolSetting, ToolSetting.audioChoices);
      expect(TtsUseCase.newMessage.toolSetting, ToolSetting.audioOnNewMessage);
      expect(
        TtsUseCase.messageClick.toolSetting,
        ToolSetting.audioOnMessageClick,
      );
    });

    test('voiceReply is the only ungated use case', () {
      final ungated = TtsUseCase.values
          .where((u) => u.toolSetting == null)
          .toList();
      expect(ungated, [TtsUseCase.voiceReply]);
    });
  });
}
