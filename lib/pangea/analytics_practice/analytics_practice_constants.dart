class AnalyticsPracticeConstants {
  static const int timeForBonus = 60;
  static const int practiceGroupSize = 10;
  static const int errorBufferSize = 5;
  static const int maxHints = 5;
  static const Duration recentPracticeCooldown = Duration(hours: 24);
  static const int minAttemptsToBypassRecentCooldown = 2;
  static const double incorrectRatioToBypassRecentCooldown = 0.5;
  static const int consecutiveCorrectToEndRetry = 2;
  static int get targetsToGenerate => practiceGroupSize + errorBufferSize;
}
