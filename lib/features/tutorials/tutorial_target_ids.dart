/// The target ids tutorials point at, in one place so a step and the widget it
/// lights are findable from each other. A widget opts in by registering the id
/// with the overlay registry; never inline the string at either end.
class TutorialTargetIds {
  /// The map surface. Not lit by any step — a hole the size of the map removes
  /// the scrim entirely — but registered as the reference frame the map projects
  /// its pin spotlights into, since pins carry no ids of their own. See
  /// [TutorialStepData.spotlightRects].
  static const String worldMapViewport = 'tutorial_world_map_viewport';

  /// The waiting room's two "you don't have to wait alone" controls, lit
  /// together as one group.
  static const String activityPlayWithBot = 'tutorial_activity_play_with_bot';
  static const String activityInviteFriends =
      'tutorial_activity_invite_friends';

  /// The floating goal-header card in an activity chat.
  static const String activityGoalHeader = 'tutorial_activity_goal_header';
}
