import 'dart:math';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_room_xp.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/quests/saved_session_xp.dart';

/// When a Mission's XP first reached its course's threshold, replayed from
/// the learner's history, for a Mission that was already complete when its
/// course's progress record began (client#9643).
///
/// The XP at each moment is what the Mission's ring counts now, over only
/// what existed then: the uses recorded by that moment and the sessions saved
/// by it. A word's XP cap keeps its earliest uses, so the uses up to a moment
/// are the ones the app counted then. The course's threshold and activities
/// are today's.
class MissionCompletionReplay {
  /// Cap-filtered uses in the learner's current language that can count
  /// toward a Mission: practice outside any session, and uses in a saved
  /// session's room.
  final List<OneConstructUse> _uses;
  final List<SavedSessionXp> _sessions;

  const MissionCompletionReplay._(this._uses, this._sessions);

  /// [uses] as `AnalyticsDataService.getUses` returns them, and [sessions]
  /// as `Client.savedSessionXp` lists them.
  factory MissionCompletionReplay({
    required Iterable<OneConstructUse> uses,
    required List<SavedSessionXp> sessions,
  }) {
    final rooms = {for (final session in sessions) session.roomId};
    return MissionCompletionReplay._([
      for (final use in uses)
        if (use.xp != 0 &&
            (use.metadata.roomId == null ||
                rooms.contains(use.metadata.roomId)))
          use,
    ], sessions);
  }

  /// When [missionId]'s XP in [outline]'s course first reached the course's
  /// threshold, or null when it never has. One pass over the Mission's own
  /// history in time order — the sessions of the activities it credits and
  /// the practice on its words, since nothing else moves its XP.
  DateTime? firstReached(CourseLoOutline outline, String missionId) {
    final sessions = _sessionsOf(outline, missionId);
    final rooms = {for (final session in sessions) session.roomId};
    final lemmas = outline.lemmasByLo[missionId] ?? const <String>{};
    final steps = [
      for (final session in sessions) _ReplayStep.save(session),
      for (final use in _uses)
        if (use.metadata.roomId == null
            ? lemmas.contains(QuestObjectiveGroup.lemmaKey(use.lemma))
            : rooms.contains(use.metadata.roomId))
          _ReplayStep.use(use),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final tally = _MissionXpTally();
    for (var i = 0; i < steps.length; i++) {
      steps[i].applyTo(tally);
      // Everything recorded at one moment counts together.
      final lastAtMoment =
          i == steps.length - 1 || steps[i + 1].at.isAfter(steps[i].at);
      if (lastAtMoment && tally.xp >= outline.xpToComplete) return steps[i].at;
    }
    return null;
  }

  /// The saved sessions [missionId] is credited with, crediting as the
  /// resolver does (activity_family.dart): each session's activity counts
  /// through its family's canonical id, and with a course copy only an
  /// activity in a family counts at all.
  List<SavedSessionXp> _sessionsOf(CourseLoOutline outline, String missionId) {
    final credit = outline.credit;
    final creditedIds = {
      for (final id in [
        ...?outline.activityIdsByLo[missionId],
        ...?credit.removedByLo[missionId],
      ])
        credit.canonicalOf(id),
    };
    return [
      for (final session in _sessions)
        if ((credit.isEmpty || credit.family.containsKey(session.activityId)) &&
            creditedIds.contains(credit.canonicalOf(session.activityId)))
          session,
    ];
  }
}

/// One step of a Mission's history: a use recorded, or a session saved.
class _ReplayStep {
  final DateTime at;
  final OneConstructUse? _use;
  final SavedSessionXp? _save;

  _ReplayStep.use(OneConstructUse use)
    : at = use.timeStamp,
      _use = use,
      _save = null;

  _ReplayStep.save(SavedSessionXp session)
    : at = session.savedAt,
      _use = null,
      _save = session;

  void applyTo(_MissionXpTally tally) {
    final use = _use;
    if (use != null) {
      tally.addUse(use);
    } else {
      tally.save(_save!);
    }
  }
}

/// A Mission's XP as its history is replayed: running sums per room and part
/// and per word, each counted at no less than zero, as the ring counts them
/// (`MissionRoomXp.of`, `MissionXpCache.practiceXpByLemmaOf`), and a
/// session's XP counted from its save.
class _MissionXpTally {
  /// Running sums, not floored: [xp] counts each at no less than zero.
  final MissionRoomXp _roomSums = MissionRoomXp.of(const []);
  final Map<String, int> _wordSums = {};
  final Set<String> _savedRooms = {};
  int xp = 0;

  void addUse(OneConstructUse use) {
    final roomId = use.metadata.roomId;
    if (roomId == null) {
      xp += _add(_wordSums, QuestObjectiveGroup.lemmaKey(use.lemma), use.xp);
      return;
    }
    final change = _add(_roomSums.partOf(use), roomId, use.xp);
    if (_savedRooms.contains(roomId)) xp += change;
  }

  void save(SavedSessionXp session) {
    _savedRooms.add(session.roomId);
    xp += session.goalXp;
    for (final part in [
      _roomSums.chat,
      _roomSums.speaking,
      _roomSums.practice,
    ]) {
      xp += max(0, part[session.roomId] ?? 0);
    }
  }

  /// Adds [delta] to [key]'s running sum in [sums], and returns how far the
  /// sum moved once floored at zero.
  static int _add(Map<String, int> sums, String key, int delta) {
    final before = sums[key] ?? 0;
    final after = before + delta;
    sums[key] = after;
    return max(0, after) - max(0, before);
  }
}
