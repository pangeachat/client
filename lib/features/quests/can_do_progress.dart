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

  /// Already complete the first time it was written, so the app never saw it
  /// complete: [firstCompletedAt] is null until it is replayed from history
  /// ([withReplayedDate]), and reconstructed rather than seen once it is set.
  final bool completedBeforeTracking;

  /// The course's threshold when the app first saw this Mission complete, set
  /// with [firstCompletedAt] and never changed after, so the Mission's meter
  /// can keep counting against it (quests.instructions.md, "A completed
  /// Mission stays complete"). Null for a date replayed from history, or one
  /// stored before the record carried it.
  final int? xpToCompleteAtFirstCompletion;

  const CanDoProgress({
    required this.xp,
    required this.breakdown,
    required this.completed,
    this.firstCompletedAt,
    this.completedBeforeTracking = false,
    this.xpToCompleteAtFirstCompletion,
  });

  static const _xpKey = 'xp';
  static const _chatKey = 'chat';
  static const _speakingKey = 'speaking';
  static const _goalsKey = 'goals';
  static const _practiceKey = 'practice';
  static const _completedKey = 'completed';
  static const _firstCompletedAtKey = 'first_completed_at';
  static const _completedBeforeTrackingKey = 'completed_before_tracking';
  static const _xpToCompleteAtFirstCompletionKey =
      'xp_to_complete_at_first_completion';

  /// Null for anything that isn't an entry: the record is read from room
  /// state another device may have written.
  static CanDoProgress? fromJson(Object? json) {
    if (json is! Map) return null;
    final firstCompletedAt = json[_firstCompletedAtKey];
    final xpToCompleteAtFirstCompletion =
        json[_xpToCompleteAtFirstCompletionKey];
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
      xpToCompleteAtFirstCompletion: xpToCompleteAtFirstCompletion is num
          ? xpToCompleteAtFirstCompletion.toInt()
          : null,
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
    if (xpToCompleteAtFirstCompletion != null)
      _xpToCompleteAtFirstCompletionKey: xpToCompleteAtFirstCompletion,
  };

  /// This entry with its completion date carried over from [before], the
  /// entry stored last time. A stored date is kept, with the threshold stored
  /// beside it. A Mission is dated [now], at [xpToComplete], only when it
  /// changes from not complete to complete; one already complete the first
  /// time it is written gets no date, because its real date is unknown and a
  /// guessed one could never be corrected.
  CanDoProgress datedAfter(
    CanDoProgress? before,
    DateTime now,
    int xpToComplete,
  ) {
    final storedDate = before?.firstCompletedAt;
    if (storedDate != null) {
      return _dated(
        firstCompletedAt: storedDate,
        completedBeforeTracking: before!.completedBeforeTracking,
        xpToCompleteAtFirstCompletion: before.xpToCompleteAtFirstCompletion,
      );
    }
    if (before?.completedBeforeTracking ?? false) {
      return _dated(completedBeforeTracking: true);
    }
    if (!completed) return _dated();
    return before == null
        ? _dated(completedBeforeTracking: true)
        : _dated(
            firstCompletedAt: now,
            xpToCompleteAtFirstCompletion: xpToComplete,
          );
  }

  /// Complete, but completed before tracking with no date yet: its date is
  /// to be replayed from history.
  bool get awaitsReplay =>
      completed && completedBeforeTracking && firstCompletedAt == null;

  /// This entry dated [at], the moment a replay of the learner's history
  /// found it first complete. Still [completedBeforeTracking], which tells a
  /// reconstructed date from a seen one.
  CanDoProgress withReplayedDate(DateTime at) =>
      _dated(firstCompletedAt: at.toUtc(), completedBeforeTracking: true);

  CanDoProgress _dated({
    DateTime? firstCompletedAt,
    bool completedBeforeTracking = false,
    int? xpToCompleteAtFirstCompletion,
  }) => CanDoProgress(
    xp: xp,
    breakdown: breakdown,
    completed: completed,
    firstCompletedAt: firstCompletedAt,
    completedBeforeTracking: completedBeforeTracking,
    xpToCompleteAtFirstCompletion: xpToCompleteAtFirstCompletion,
  );
}
