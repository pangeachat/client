class TutorialConstants {
  static const String sequenceOverlayKey = 'tutorial_sequence';

  /// A beat held at the end of a step that navigated somewhere, before the next
  /// step's message appears — long enough for the learner to see what just
  /// opened rather than reading the next instruction over it.
  static const Duration stepSettleDelay = Duration(seconds: 1);

  /// How long a step holds a demonstration on screen (a highlighted token, a
  /// translation) before advancing — long enough to read what was shown,
  /// short enough not to read as a hang. The card is hidden for the wait, so
  /// every extra second here is dead air.
  static const Duration stepDemoDelay = Duration(milliseconds: 2500);

  /// How close to the bottom (pixels, reverse list) still counts as "scrolled
  /// to the bottom" for the chat tutorial's gate. A reverse list rarely rests
  /// at exactly 0 — keyboard insets, momentum, spacers all leave a residue.
  static const double scrolledToBottomThreshold = 32.0;
}
