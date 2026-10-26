import 'package:fluffychat/features/quests/quest_progression_resolver.dart';

/// One Mission's entry in a course's progress record (client#9643): its XP as
/// the Mission's ring shows it, that XP's parts as its split shows them, and
/// whether it shows as complete. The JSON names are the teacher dashboard's,
/// which calls Missions Can-Dos.
class CanDoProgress {
  final int xp;
  final MissionXpBreakdown breakdown;
  final bool completed;

  /// When the app first saw this Mission complete. Never cleared or moved
  /// once set, even when its XP falls or the threshold rises.
  final DateTime? firstCompletedAt;

  /// Already complete the first time it was written, so the date it was
  /// completed is unknown.
  final bool completedBeforeTracking;

  const CanDoProgress({
    required this.xp,
    required this.breakdown,
    required this.completed,
    this.firstCompletedAt,
    this.completedBeforeTracking = false,
  });

  static const _xpKey = 'xp';
  static const _chatKey = 'chat';
  static const _speakingKey = 'speaking';
  static const _goalsKey = 'goals';
  static const _practiceKey = 'practice';
  static const _completedKey = 'completed';
  static const _firstCompletedAtKey = 'first_completed_at';
  static const _completedBeforeTrackingKey = 'completed_before_tracking';

  /// Null for anything that isn't an entry: the record is read from room
  /// state another device may have written.
  static CanDoProgress? fromJson(Object? json) {
    if (json is! Map) return null;
    final firstCompletedAt = json[_firstCompletedAtKey];
    return CanDoProgress(
      xp: _intOf(json[_xpKey]),
      breakdown: MissionXpBreakdown(
        chat: _intOf(json[_chatKey]),
        speaking: _intOf(json[_speakingKey]),
        goals: _intOf(json[_goalsKey]),
        practice: _intOf(json[_practiceKey]),
      ),
      completed: json[_completedKey] == true,
      firstCompletedAt: firstCompletedAt is String
          ? DateTime.tryParse(firstCompletedAt)?.toUtc()
          : null,
      completedBeforeTracking: json[_completedBeforeTrackingKey] == true,
    );
  }

  static int _intOf(Object? value) => value is num ? value.toInt() : 0;

  Map<String, Object?> toJson() => {
    _xpKey: xp,
    _chatKey: breakdown.chat,
    _speakingKey: breakdown.speaking,
    _goalsKey: breakdown.goals,
    _practiceKey: breakdown.practice,
    _completedKey: completed,
    _firstCompletedAtKey: firstCompletedAt?.toUtc().toIso8601String(),
    if (completedBeforeTracking) _completedBeforeTrackingKey: true,
  };

  /// This entry with its completion date carried over from [before], the
  /// entry stored last time. A stored date is kept. A Mission is dated [now]
  /// only when it changes from not complete to complete; one already complete
  /// the first time it is written gets no date, because its real date is
  /// unknown and a guessed one could never be corrected.
  CanDoProgress datedAfter(CanDoProgress? before, DateTime now) {
    final storedDate = before?.firstCompletedAt;
    if (storedDate != null) return _dated(firstCompletedAt: storedDate);
    if (before?.completedBeforeTracking ?? false) {
      return _dated(completedBeforeTracking: true);
    }
    if (!completed) return _dated();
    return before == null
        ? _dated(completedBeforeTracking: true)
        : _dated(firstCompletedAt: now);
  }

  CanDoProgress _dated({
    DateTime? firstCompletedAt,
    bool completedBeforeTracking = false,
  }) => CanDoProgress(
    xp: xp,
    breakdown: breakdown,
    completed: completed,
    firstCompletedAt: firstCompletedAt,
    completedBeforeTracking: completedBeforeTracking,
  );
}
