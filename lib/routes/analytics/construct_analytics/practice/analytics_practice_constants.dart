class AnalyticsPracticeConstants {
  static const int timeForBonus = 60;
  static const int practiceGroupSize = 10;
  static const int errorBufferSize = 5;
  static const int maxHints = 5;
  static const Duration recentPracticeCooldown = Duration(hours: 24);

  /// How long a right answer stays on screen before practice moves on. Message
  /// practice holds its answers for the same beat, so the two feel alike.
  static const Duration correctAnswerHold = Duration(milliseconds: 1000);

  /// How long a live session may sit without user interaction before it is
  /// auto-ended. See practice-exercises.instructions.md § Session Persistence
  /// & Lifecycle.
  static const Duration idleTimeout = Duration(minutes: 30);
  static const int minAttemptsToBypassRecentCooldown = 2;
  static const double incorrectRatioToBypassRecentCooldown = 0.5;
  static const int consecutiveCorrectToEndRetry = 2;

  /// The most words a read-aloud item asks the learner to read: a window of
  /// the example message around the target word. See
  /// practice-exercises.instructions.md, "Speaking practice".
  static const int readAloudMaxWords = 8;
  static int get targetsToGenerate => practiceGroupSize + errorBufferSize;
}
