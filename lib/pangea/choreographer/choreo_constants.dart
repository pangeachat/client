class ChoreoConstants {
  static const int msBeforeIGCStart = 10000;
  static const int maxLength = 1000;
  static const String inputTransformTargetKey = 'input_text_field';
  static const int defaultErrorBackoffSeconds = 5;

  static const String srcLang = 'src_lang';
  static const String tgtLang = 'tgt_lang';
  static const String lang = 'lang';
  static const String deepL = 'deepl';
  static const String allDetections = 'all_detections';
  static const String confidence = 'confidence';
  static const String text = 'text';
  static const String tokenFeedbackEdit = 'edit_word_info';
  static const String feedback = 'feedback';
  static const String content = 'content';
  static const String score = 'score';

  static const String prevMessages = 'prev_messages';
  static const String prevContent = 'prev_content';
  static const String prevSender = 'prev_sender';
  static const String prevTimestamp = 'prev_timestamp';

  static const String enableIGC = 'enable_igc';
  static const String enableIT = 'enable_it';

  static const String incorrectCompleteIgcFeedback =
      "All corrections have been completed, but the message still contains error.";
}
