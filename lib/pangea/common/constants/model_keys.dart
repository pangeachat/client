class ModelKey {
  static const String userId = 'user_id';
  static const String targetLanguage = 'target_language';
  static const String sourceLanguage = 'source_language';
  static const String userL1 = 'user_l1';
  static const String userL2 = 'user_l2';
  static const String langCode = 'lang_code';
  // some old analytics rooms have langCode instead of lang_code in the room creation content
  static const String oldLangCode = 'langCode';

  static const String fullText = 'full_text';
  static const String tokens = 'tokens';
  static const String offset = 'offset';
  static const String length = 'length';
  static const String lemma = 'lemma';

  static const String voice = 'voice';

  static const String joinRule = 'join_rule';
}
