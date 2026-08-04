import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';

/// The surface a TTS request comes from, mapping each request to the
/// per-surface audio toggle that gates it in learning settings.
enum TtsUseCase {
  /// Tap-a-word audio: word cards, word selection, vocab lists.
  words,

  /// Practice and multiple-choice audio: answer choices, correct-answer
  /// reinforcement, match items.
  choices,

  /// Automatic read-aloud of received messages.
  incomingMessage;

  ToolSetting get toolSetting {
    switch (this) {
      case TtsUseCase.words:
        return ToolSetting.audioWords;
      case TtsUseCase.choices:
        return ToolSetting.audioChoices;
      case TtsUseCase.incomingMessage:
        return ToolSetting.audioIncomingMessages;
    }
  }
}
