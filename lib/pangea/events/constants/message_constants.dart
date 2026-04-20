class MessageConstants {
  static const String originalWritten = 'original_written';
  static const String tokensSent = 'tokens_sent';
  static const String tokensWritten = 'tokens_written';
  static const String choreoRecord = 'choreo_record';

  /// This is strictly for use in message content jsons
  /// in order to flag that the message edit was done in order
  /// to edit some message data such as tokens, morph tags, etc.
  /// This will help us know to omit the message from notifications,
  /// bot responses, etc. It will also help use find the message if
  /// we want to gather user edits for LLM fine-tuning.
  static const String messageTags = 'p.tag';
  static const String messageTagActivityPlan = 'activity_plan';

  static const String transcription = 'transcription';
  static const String botTranscription = 'bot_transcription';
  static const String userStt = 'user_stt';
  static const String duration = 'duration';
}
