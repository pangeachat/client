class TutorialConstants {
  static const String sequenceOverlayKey = 'tutorial_sequence';

  /// A beat held at the end of a step that navigated somewhere, before the next
  /// step's message appears — long enough for the learner to see what just
  /// opened rather than reading the next instruction over it.
  static const Duration stepSettleDelay = Duration(seconds: 1);
}
