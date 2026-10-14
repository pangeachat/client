import 'dart:math';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';

extension QuestsClientExtension on Client {
  /// The learner's goal checkmarks per activity: their best single session's
  /// orchestrator-awarded goals. Drawn on activity cards and map pins; it no
  /// longer decides Mission completion, which [userXpByActivity] feeds.
  Map<String, int> get userStarsByActivity {
    final stars = <String, int>{};
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null) continue;

      final current = stars[activityId] ?? 0;
      final collected = room.ownCompletedGoals.length;
      stars[activityId] = max(current, collected);
    }
    return stars;
  }

  /// The learner's activity XP per activity: every SAVED session of it, each
  /// counting the XP credited to its room ([creditedXpByRoom] — the chat XP
  /// earned there plus practice credited to it, MissionXpCache) and a flat
  /// [kGoalXp] per goal the learner was awarded in it. Repeat sessions
  /// accumulate — XP is effort — and a session counts only once it is saved,
  /// so finishing is what banks it (org activities doc, "Activity XP" and
  /// "Saving"; quests.instructions.md, "What fills a Mission").
  Map<String, int> userXpByActivity(Map<String, int> creditedXpByRoom) {
    final xp = <String, int>{};
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null || !room.hasArchivedActivity) continue;
      final xpOfSession = sessionXp(room, creditedXpByRoom);
      if (xpOfSession <= 0) continue;
      xp[activityId] = (xp[activityId] ?? 0) + xpOfSession;
    }
    return xp;
  }

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

  /// One session's XP: the XP credited to its room plus its goal checkmarks.
  /// What [userXpByActivity] banks once the session is saved, and what the
  /// goal header's ring shows while it runs.
  int sessionXp(Room room, Map<String, int> creditedXpByRoom) =>
      (creditedXpByRoom[room.id] ?? 0) +
      kGoalXp * room.ownCompletedGoals.length;
}
