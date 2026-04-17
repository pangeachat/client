class AnalyticsConstants {
  static const int xpPerLevel = 500;
  static const int vocabUseMaxXP = 30;
  static const int morphUseMaxXP = 500;
  static const int xpForGreens = 50;
  static const int xpForFlower = 100;
  static const String seedSvgFileName = "Seed.svg";
  static const String leafSvgFileName = "Leaf.svg";
  static const String flowerSvgFileName = "Flower.svg";
  static const String emojiForSeed = "🫛";
  static const String emojiForGreen = "🌱";
  static const String emojiForFlower = "🌸";
  static const levelUpAudioFileName = "LevelUp_chime.mp3";
  static const levelUpImageFileName = "LvL_Up_Full_Banner.png";
  static const vocabIconFileName = "Vocabulary_icon.png";
  static const morphIconFileName = "grammar_icon.png";

  /// Default days-since-last-used when a construct has never been practiced.
  static const int defaultDaysSinceLastUsed = 20;

  /// Multiplier for content words (nouns, verbs, adjectives).
  static const int contentWordMultiplier = 10;

  /// Multiplier for function words (articles, prepositions).
  static const int functionWordMultiplier = 7;

  /// Bonus multiplier applied to active-tier constructs.
  static const int activeTierMultiplier = 2;

  static const String analytics = 'analytics';
  static const String level = 'level';
  static const String xpOffset = 'xp_offset';
  static const String analyticsRoomId = 'analytics_room_id';
  static const String roomIds = 'room_ids';
}
