/// What the Android app asks the learner for next, so that a call can ring
/// this phone while the app is closed. See voice-video-calls.instructions.md,
/// "Notifications on Android".
enum CallRingingAsk {
  none,

  /// Up front, before any call has come in.
  notifications,

  /// After a call that could not ring because notifications were off.
  notificationsAfterMissedRing,

  /// After a ring that could only show as a heads-up notification.
  fullScreen;

  /// Notifications first, since the ring is one: full screen cannot help
  /// while they are off.
  static CallRingingAsk next({
    required bool notificationsOn,
    required bool askedForNotifications,
    required bool missedRingForNotifications,
    required bool fullScreenWanted,
  }) {
    if (notificationsOn) return fullScreenWanted ? fullScreen : none;
    if (missedRingForNotifications) return notificationsAfterMissedRing;
    return askedForNotifications ? none : notifications;
  }
}
