/// Remembers that the learner chose "Play with a bot" on an activity, across
/// the hop from the start page to the role picker, so the session it launches
/// gets the bot as soon as it exists (#9333 prototype). In memory only: a
/// reload mid-hop falls back to the plain waiting room, where the bot is
/// still one tap away.
class PlayWithBotIntent {
  static final Set<String> _activityIds = {};

  static void set(String activityId, {required bool withBot}) =>
      withBot ? _activityIds.add(activityId) : _activityIds.remove(activityId);

  /// Whether the launch of [activityId] should add the bot; clears the intent.
  static bool consume(String activityId) => _activityIds.remove(activityId);
}
