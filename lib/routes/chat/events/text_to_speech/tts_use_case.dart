import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';

/// The surface a TTS request comes from, mapping each request to the
/// per-surface audio toggle that gates it in learning settings.
enum TtsUseCase {
  /// Tap-a-word audio: word cards, word selection, vocab lists.
  words,

  /// Practice and multiple-choice audio: answer choices, correct-answer
  /// reinforcement, match items.
  choices,

  /// Automatic read-aloud of newly received messages.
  newMessage,

  /// Read-aloud of a message the learner clicked.
  messageClick,

  /// The bot's reply to a voice message the learner just sent.
  ///
  /// Ungated on purpose: `audioOnNewMessage` governs *unprompted* audio —
  /// messages arriving unbidden while the chat is open. A reply to something
  /// the learner just said out loud is not unprompted, and it is bounded by
  /// their own voice messages rather than by how much other people type. The
  /// bot used to speak these itself, unconditionally and always via paid TTS;
  /// this keeps them audible while routing device-first.
  voiceReply;

  /// The toggle that gates this use case, or null when it is ungated.
  ToolSetting? get toolSetting {
    switch (this) {
      case TtsUseCase.words:
        return ToolSetting.audioWords;
      case TtsUseCase.choices:
        return ToolSetting.audioChoices;
      case TtsUseCase.newMessage:
        return ToolSetting.audioOnNewMessage;
      case TtsUseCase.messageClick:
        return ToolSetting.audioOnMessageClick;
      case TtsUseCase.voiceReply:
        return null;
    }
  }
}
