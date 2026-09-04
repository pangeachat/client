/// The target ids tutorials point at, in one place so a step and the widget it
/// lights are findable from each other. A widget opts in by registering the id
/// with the overlay registry; never inline the string at either end.
class TutorialTargetIds {
  /// The floating goal-header card in an activity chat.
  static const String activityGoalHeader = 'tutorial_activity_goal_header';

  /// The course-wide progress bar on the course page's intro block. Claimed
  /// there only — the bar also renders in the pushed full-plan subpage, which
  /// can be mounted at the same time ([TutorialTarget]).
  static const String courseProgressBar = 'tutorial_course_progress_bar';

  /// The world map's own viewport, used as the coordinate origin the map
  /// projects a chosen pin's position into. The map is one persistent instance,
  /// so this has a single claimant by construction.
  static const String worldMapViewport = 'tutorial_world_map_viewport';

  /// The whole course panel — header, progress bar and plan sections together.
  /// Claimed by the panel that renders a `course` token, which is one widget on
  /// both layouts: the wide left column and the narrow nav cavity host the same
  /// tree, and they are mutually exclusive.
  static const String coursePanel = 'tutorial_course_panel';

  /// The course page's Activities row — the ranked, Mission-less carousel of
  /// the plan's activities (quests.instructions.md).
  ///
  /// The carousel rather than its individual cards: a card would need an id per
  /// activity, and the ranking re-orders continuously, so no card is a stable
  /// claimant. The row is one widget on the course page, so it has exactly one.
  static const String courseActivities = 'tutorial_course_activities';

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
