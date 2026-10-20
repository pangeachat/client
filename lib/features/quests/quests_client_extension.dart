import 'dart:math';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/course_language_scope.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

extension QuestsClientExtension on Client {
  /// The learner's goal checkmarks per activity: their best single session's
  /// orchestrator-awarded goals. Drawn on activity cards and map pins; Mission
  /// completion is XP ([userXpByActivity]).
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
  /// accumulate — XP is effort — and a session counts only once it is saved, so
  /// finishing is what banks it (org activities doc, "Activity XP" and
  /// "Saving"; quests.instructions.md, "What fills a Mission"). Only sessions
  /// in the learner's current language count
  /// ([CourseLanguageScope.savedSessionInTargetLanguage]).
  Map<String, int> userXpByActivity(Map<String, int> creditedXpByRoom) {
    final xp = <String, int>{};
    final inLanguage = CourseLanguageScope.savedSessionIdsInTargetLanguage(
      this,
    );
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null ||
          !room.hasArchivedActivity ||
          !CourseLanguageScope.savedSessionInTargetLanguage(room, inLanguage)) {
        continue;
      }
      final xpOfSession = sessionXp(room, creditedXpByRoom);
      if (xpOfSession <= 0) continue;
      xp[activityId] = (xp[activityId] ?? 0) + xpOfSession;
    }
    return xp;
  }

  /// [userXpByActivity] split by source: the same saved sessions, with each
  /// room's chat, speaking and practice XP kept apart and the goal checkmarks
  /// on their own. Feeds the Mission meters' split by source.
  Map<String, MissionXpBreakdown> userXpBreakdownByActivity({
    required Map<String, int> chatXpByRoom,
    required Map<String, int> practiceXpByRoom,
    Map<String, int> speakingXpByRoom = const {},
  }) {
    final xp = <String, MissionXpBreakdown>{};
    final inLanguage = CourseLanguageScope.savedSessionIdsInTargetLanguage(
      this,
    );
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null ||
          !room.hasArchivedActivity ||
          !CourseLanguageScope.savedSessionInTargetLanguage(room, inLanguage)) {
        continue;
      }
      final session = MissionXpBreakdown(
        chat: chatXpByRoom[room.id] ?? 0,
        speaking: speakingXpByRoom[room.id] ?? 0,
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
      speakingXpByRoom: cache.speakingXpByRoom,
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
        group.lemmas,
        MissionXpCache.instance.practiceXpByLemma,
      ),
    );
    for (final activity in group.activities) {
      sum = sum + (perActivity[activity.activityId] ?? MissionXpBreakdown.zero);
    }
    return sum;
  }

  /// [group]'s XP by the skill it exercised — writing, speaking, listening,
  /// reading — over the same inputs as [missionXpBreakdown]: its activities'
  /// saved sessions and practice outside any session on its words. Goals are
  /// no skill and are not in it (their XP is [MissionXpBreakdown.goals]).
  /// Listening counts listening exercises only: hearing a message read aloud
  /// earns no XP.
  Map<LearningSkillsEnum, int> missionSkillXp(QuestObjectiveGroup group) {
    final cache = MissionXpCache.instance;
    final activityIds = {for (final a in group.activities) a.activityId};
    final xp = <LearningSkillsEnum, int>{};
    final inLanguage = CourseLanguageScope.savedSessionIdsInTargetLanguage(
      this,
    );
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null ||
          !activityIds.contains(activityId) ||
          !room.hasArchivedActivity ||
          !CourseLanguageScope.savedSessionInTargetLanguage(room, inLanguage)) {
        continue;
      }
      _addSkills(xp, cache.skillXpByRoom[room.id]);
    }
    for (final lemma in group.lemmas) {
      _addSkills(xp, cache.skillXpByLemma[lemma]);
    }
    return xp;
  }

  /// Adds each of [skills]' XP into [into].
  static void _addSkills(
    Map<LearningSkillsEnum, int> into,
    Map<LearningSkillsEnum, int>? skills,
  ) => skills?.forEach(
    (skill, value) => into[skill] = (into[skill] ?? 0) + value,
  );

  /// [missionId]'s group in the first joined course in the learner's current
  /// language that carries it, as that course shows it (its copy, else its
  /// pins). Null when none does — a stale link, a course since left, or a
  /// Mission only another language's course holds.
  Future<QuestObjectiveGroup?> joinedMissionGroup(String missionId) async {
    // Only courses in the learner's current language: the same Mission can
    // sit in a course of another language, whose word list would match none
    // of this language's words (#9559).
    for (final room in joinedCourseRooms.where(
      CourseLanguageScope.courseInTargetLanguage,
    )) {
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
