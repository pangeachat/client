import 'dart:math';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// One value per activity from its sessions' [(activityId, stars)] pairs: the
/// best session's. The per-member reduction every stars reader applies before
/// crediting a family (activity_family.dart).
Map<String, int> bestStarsByActivity(
  Iterable<({String activityId, int stars})> sessions,
) {
  final best = <String, int>{};
  for (final session in sessions) {
    best[session.activityId] = max(
      best[session.activityId] ?? 0,
      session.stars,
    );
  }
  return best;
}

/// One value per activity from its saved sessions' [(activityId, xp)] pairs:
/// every session with XP summed (XP is effort, so repeats accumulate). The per-member
/// reduction the XP readers apply before crediting a family
/// (activity_family.dart).
Map<String, int> sumXpByActivity(
  Iterable<({String activityId, int xp})> sessions,
) {
  final xp = <String, int>{};
  for (final session in sessions) {
    // A session that earned nothing leaves no entry.
    if (session.xp <= 0) continue;
    xp[session.activityId] = (xp[session.activityId] ?? 0) + session.xp;
  }
  return xp;
}

extension QuestsClientExtension on Client {
  /// The learner's goal checkmarks per activity: their best single session's
  /// orchestrator-awarded goals. Drawn on activity cards and map pins; Mission
  /// completion is XP ([userXpByActivity]).
  /// Raw per member: readers that answer for a course credit it across the
  /// activity's copies ([CourseCredit], activity_family.dart).
  Map<String, int> get userStarsByActivity => bestStarsByActivity([
    for (final room in rooms)
      if (room.activityId != null)
        (activityId: room.activityId!, stars: room.ownCompletedGoals.length),
  ]);

  /// The learner's activity XP per activity: every SAVED session of it, each
  /// counting the XP credited to its room ([creditedXpByRoom] — the chat XP
  /// earned there plus practice credited to it, MissionXpCache) and a flat
  /// [kGoalXp] per goal the learner was awarded in it. Repeat sessions
  /// accumulate — XP is effort — and a session counts only once it is saved,
  /// so finishing is what banks it (org activities doc, "Activity XP" and
  /// "Saving"; quests.instructions.md, "What fills a Mission").
  ///
  /// Raw per member: readers that answer for a course credit it across the
  /// activity's copies ([CourseCredit.creditedBy]).
  Map<String, int> userXpByActivity(Map<String, int> creditedXpByRoom) =>
      sumXpByActivity([
        for (final room in rooms)
          if (room.activityId != null && room.hasArchivedActivity)
            (
              activityId: room.activityId!,
              xp: sessionXp(room, creditedXpByRoom),
            ),
      ]);

  /// [userXpByActivity] split by source: the same saved sessions, with each
  /// room's chat and practice XP kept apart and the goal checkmarks on their
  /// own. Feeds the Mission card's ring.
  Map<String, MissionXpBreakdown> userXpBreakdownByActivity({
    required Map<String, int> chatXpByRoom,
    required Map<String, int> practiceXpByRoom,
  }) {
    final xp = <String, MissionXpBreakdown>{};
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null || !room.hasArchivedActivity) continue;
      final session = MissionXpBreakdown(
        chat: chatXpByRoom[room.id] ?? 0,
        goals: kGoalXp * room.ownCompletedGoals.length,
        practice: practiceXpByRoom[room.id] ?? 0,
      );
      if (session.total <= 0) continue;
      xp[activityId] = (xp[activityId] ?? MissionXpBreakdown.zero) + session;
    }
    return xp;
  }

  /// [userXpBreakdownByActivity] read from the shared [MissionXpCache].
  Map<String, MissionXpBreakdown> get cachedXpBreakdownByActivity {
    final cache = MissionXpCache.instance;
    return userXpBreakdownByActivity(
      chatXpByRoom: cache.chatXpByRoom,
      practiceXpByRoom: cache.practiceXpByRoom,
    );
  }

  /// [group]'s XP by source: its activities' saved sessions plus practice
  /// outside any session on its words — what the resolver totals for it.
  /// Pass [byActivity] ([cachedXpBreakdownByActivity]) when breaking down
  /// several Missions at once, so the rooms are walked once.
  MissionXpBreakdown missionXpBreakdown(
    QuestObjectiveGroup group, {
    Map<String, MissionXpBreakdown>? byActivity,
  }) {
    final perActivity = byActivity ?? cachedXpBreakdownByActivity;
    var sum = MissionXpBreakdown(
      practice: MissionXpBreakdown.practiceFor(
        group.creditedLemmas,
        MissionXpCache.instance.practiceXpByLemma,
      ),
    );
    final credit = group.credit;
    if (credit.isEmpty) {
      for (final activity in group.activities) {
        sum =
            sum + (perActivity[activity.activityId] ?? MissionXpBreakdown.zero);
      }
      return sum;
    }
    // Every member of an activity's family counts toward the member the
    // course shows, hidden activities included (activity_family.dart).
    final byCanonical = <String, MissionXpBreakdown>{};
    for (final entry in perActivity.entries) {
      if (!credit.family.containsKey(entry.key)) continue;
      final canonical = credit.canonicalOf(entry.key);
      byCanonical[canonical] =
          (byCanonical[canonical] ?? MissionXpBreakdown.zero) + entry.value;
    }
    final ids = {
      for (final a in group.activities) credit.canonicalOf(a.activityId),
      for (final id
          in credit.removedByLo[group.objective.id] ?? const <String>[])
        credit.canonicalOf(id),
    };
    for (final id in ids) {
      sum = sum + (byCanonical[id] ?? MissionXpBreakdown.zero);
    }
    return sum;
  }

  /// [missionId]'s group in the first joined course that carries it, as that
  /// course shows it (its copy, else its pins). Null when no joined course
  /// does — a stale link, or a course since left.
  Future<QuestObjectiveGroup?> joinedMissionGroup(String missionId) async {
    for (final room in joinedCourseRooms) {
      final questId = room.coursePlan?.uuid;
      if (questId == null) continue;
      final outline = (await QuestRepo.outline(
        questId,
        courseRoomId: room.id,
      )).result;
      // silent-ok: a course whose outline fails is reported where it loads
      // (reportCourseOutlineFailure); the next joined course may carry it.
      if (outline == null) continue;
      for (final group in outline.forCourse(room).groups) {
        if (group.objective.id == missionId) return group;
      }
    }
    return null;
  }

  /// One session's XP: the XP credited to its room plus its goal checkmarks.
  /// What [userXpByActivity] banks once the session is saved, and what the
  /// goal header's ring shows while it runs.
  int sessionXp(Room room, Map<String, int> creditedXpByRoom) =>
      (creditedXpByRoom[room.id] ?? 0) +
      kGoalXp * room.ownCompletedGoals.length;
}
