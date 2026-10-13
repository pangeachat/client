/// Remembers that the learner chose "Play with Pangea Bot" on an activity, across
/// the hop from the start page to the role picker, so the session it launches
/// gets the bot as soon as it exists (#9333). In memory only: a
/// reload mid-hop falls back to the plain waiting room, where the bot is
/// still one tap away. An intent only counts within [_validFor] of being set,
/// so one left behind by an abandoned launch can't add the bot to a later one.
class PlayWithBotIntent {
  static const Duration _validFor = Duration(minutes: 5);

  static final Map<String, DateTime> _setAt = {};

  static void set(String activityId, {required bool withBot}) =>
      withBot ? _setAt[activityId] = DateTime.now() : _setAt.remove(activityId);

  /// Whether the launch of [activityId] should add the bot; clears the intent.
  static bool consume(String activityId) {
    final setAt = _setAt.remove(activityId);
    return setAt != null && DateTime.now().difference(setAt) < _validFor;
  }

  /// Forget every intent — on logout or account switch.
  static void clear() => _setAt.clear();
}
