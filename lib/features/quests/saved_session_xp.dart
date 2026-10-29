/// One saved activity session as Mission XP counts it: the activity it is
/// of, its room, when it was saved — the moment its XP starts to count — and
/// what its goals pay. What the completion replay cuts by time
/// (`MissionCompletionReplay`).
class SavedSessionXp {
  final String activityId;
  final String roomId;
  final DateTime savedAt;
  final int goalXp;

  const SavedSessionXp({
    required this.activityId,
    required this.roomId,
    required this.savedAt,
    required this.goalXp,
  });
}
