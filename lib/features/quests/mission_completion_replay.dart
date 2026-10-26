import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_room_xp.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/quests/saved_session_xp.dart';

/// When a Mission's XP first reached its course's threshold, replayed from
/// the learner's history, for a Mission that was already complete when its
/// course's progress record began (client#9643).
///
/// The XP at each moment is counted by the rules the Mission's ring uses now,
/// over only what existed then: the uses recorded by that moment and the
/// sessions saved by it. A word's XP cap keeps its earliest uses, so the uses
/// a cut keeps are the ones the app counted at that moment. The course's
/// threshold and activities are today's.
class MissionCompletionReplay {
  /// Cap-filtered uses in the learner's current language that can count
  /// toward a Mission: practice outside any session, and uses in a saved
  /// session's room.
  final List<OneConstructUse> _uses;
  final List<SavedSessionXp> _sessions;
  final Map<String, DateTime> _savedAtByRoom;

  const MissionCompletionReplay._({
    required List<OneConstructUse> uses,
    required List<SavedSessionXp> sessions,
    required Map<String, DateTime> savedAtByRoom,
  }) : _uses = uses,
       _sessions = sessions,
       _savedAtByRoom = savedAtByRoom;

  /// [uses] as `AnalyticsDataService.getUses` returns them, and [sessions]
  /// as `Client.savedSessionXp` lists them.
  factory MissionCompletionReplay({
    required Iterable<OneConstructUse> uses,
    required List<SavedSessionXp> sessions,
  }) {
    final savedAtByRoom = {
      for (final session in sessions) session.roomId: session.savedAt,
    };
    return MissionCompletionReplay._(
      uses: [
        for (final use in uses)
          if (use.metadata.roomId == null ||
              savedAtByRoom.containsKey(use.metadata.roomId))
            use,
      ],
      sessions: sessions,
      savedAtByRoom: savedAtByRoom,
    );
  }

  /// When [missionId]'s XP in [outline]'s course first reached the course's
  /// threshold, or null when it never has.
  ///
  /// Only the Mission's own history is replayed — the sessions of the
  /// activities it credits and the practice on its words — since nothing else
  /// moves its XP; the replay runs while the app is in use.
  DateTime? firstReached(CourseLoOutline outline, String missionId) {
    final lemmas = outline.lemmasByLo[missionId] ?? const <String>{};
    final credit = outline.credit;
    final creditedIds = {
      for (final id in [
        ...?outline.activityIdsByLo[missionId],
        ...?credit.removedByLo[missionId],
      ])
        credit.canonicalOf(id),
    };
    final sessions = [
      for (final session in _sessions)
        if (creditedIds.contains(credit.canonicalOf(session.activityId)))
          session,
    ];
    final rooms = {for (final session in sessions) session.roomId};
    final uses = [
      for (final use in _uses)
        if (use.metadata.roomId == null
            ? lemmas.contains(QuestObjectiveGroup.lemmaKey(use.lemma))
            : rooms.contains(use.metadata.roomId))
          use,
    ];
    for (final moment in _momentsXpCanRise(sessions, uses)) {
      final xp = _xpAt(moment, uses, sessions, outline, missionId);
      if (xp >= outline.xpToComplete) return moment;
    }
    return null;
  }

  /// The moments [sessions] and [uses] can raise a Mission's XP, oldest
  /// first: each session's save, and each XP-earning use that counts as soon
  /// as it is recorded — practice outside any session, or a use in a
  /// session's room after the session was saved.
  List<DateTime> _momentsXpCanRise(
    List<SavedSessionXp> sessions,
    List<OneConstructUse> uses,
  ) => {
    for (final session in sessions) session.savedAt,
    for (final use in uses)
      if (use.xp > 0 && _countsWhenRecorded(use)) use.timeStamp,
  }.toList()..sort();

  bool _countsWhenRecorded(OneConstructUse use) {
    final roomId = use.metadata.roomId;
    return roomId == null || use.timeStamp.isAfter(_savedAtByRoom[roomId]!);
  }

  /// [missionId]'s XP in [outline]'s course as the ring would have counted
  /// it at [moment], from [uses] and [sessions].
  int _xpAt(
    DateTime moment,
    List<OneConstructUse> uses,
    List<SavedSessionXp> sessions,
    CourseLoOutline outline,
    String missionId,
  ) {
    final usesByThen = [
      for (final use in uses)
        if (!use.timeStamp.isAfter(moment)) use,
    ];
    final credited = MissionRoomXp.of(usesByThen).credited;
    final xpByActivity = sumXpByActivity([
      for (final session in sessions)
        if (!session.savedAt.isAfter(moment))
          (
            activityId: session.activityId,
            xp: (credited[session.roomId] ?? 0) + session.goalXp,
          ),
    ]);
    return resolveProgression(
          outlines: [outline],
          xpByActivity: xpByActivity,
          practiceXpByLemma: MissionXpCache.practiceXpByLemmaOf(usesByThen),
        ).quests.firstOrNull?.rollup[missionId]?.xp ??
        0;
  }
}
