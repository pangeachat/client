/// The target ids tutorials point at, in one place so a step and the widget it
/// lights are findable from each other. A widget opts in by registering the id
/// with the overlay registry; never inline the string at either end.
class TutorialTargetIds {
  /// The waiting room's two "you don't have to wait alone" controls, lit
  /// together as one group.
  static const String activityPlayWithBot = 'tutorial_activity_play_with_bot';
  static const String activityInviteFriends =
      'tutorial_activity_invite_friends';

  /// The floating goal-header card in an activity chat.
  static const String activityGoalHeader = 'tutorial_activity_goal_header';

  /// The activity carousel of a course plan's "Up next" Mission.
  ///
  /// The carousel rather than its individual cards: a card would need an id per
  /// activity, and the same activity can appear under more than one Mission, so
  /// two cards would contend for one GlobalKey. Exactly one Mission is ever the
  /// anchor, so this id has one claimant.
  static const String courseUpNextActivities =
      'tutorial_course_up_next_activities';

  /// Nav destinations. One id each, shared by the wide rail and the narrow
  /// bottom nav: they are mutually exclusive by layout, so whichever tree is
  /// mounted answers and no id has two claimants.
  static const String navWorld = 'tutorial_nav_world';
  static const String navChats = 'tutorial_nav_chats';
  static const String navCourses = 'tutorial_nav_courses';

  /// The Vocabulary tracker — the way into analytics, in the wide powerups
  /// cluster or the narrow analytics bar (again mutually exclusive).
  static const String analyticsVocabTracker = 'tutorial_analytics_vocab';

  /// The Practice button on an analytics panel. Per construct type, because the
  /// vocabulary and grammar panels are the same widget and either may be open.
  static String analyticsPracticeButton(String constructTypeName) =>
      'tutorial_practice_button_$constructTypeName';
}
