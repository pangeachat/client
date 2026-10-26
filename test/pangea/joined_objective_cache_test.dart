import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/chat/chat_details/teacher_mode_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';
import 'courses/course_missions_fixtures.dart';
import 'get_test_client.dart';

CourseLoOutline _outline(
  List<String> los, {
  String courseId = 'c1',
  String? questId,
}) => CourseLoOutline(
  courseId: courseId,
  questId: questId,
  orderedLoIds: los,
  activityIdsByLo: const {},
);

void main() {
  group('JoinedObjectiveCache.rebuild', () {
    test('ids and outlines start empty before any rebuild', () {
      final cache = JoinedObjectiveCache();
      expect(cache.ids, isEmpty);
      expect(cache.outlines, isEmpty);
    });

    test('unions and dedups objective ids across joined courses', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild(
        ['c1', 'c2'],
        outlineOf: (u) async =>
            _outline(u == 'c1' ? ['lo-a', 'lo-b'] : ['lo-b', 'lo-c']),
      );
      expect(cache.ids, {'lo-a', 'lo-b', 'lo-c'});
      expect(cache.outlines.length, 2);
    });

    test('keeps each course outline ordered for the gate', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild([
        'c1',
      ], outlineOf: (u) async => _outline(['lo-1', 'lo-2', 'lo-3']));
      expect(cache.outlines.single.orderedLoIds, ['lo-1', 'lo-2', 'lo-3']);
    });

    test('applies the per-course XP-to-complete override', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild(
        ['c1'],
        outlineOf: (u) async => _outline(['lo-a']),
        xpToCompleteOf: (u) => 500,
      );
      expect(cache.outlines.single.xpToComplete, 500);
    });

    test('defaults the threshold when no override is given', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild(['c1'], outlineOf: (u) async => _outline(['lo-a']));
      expect(cache.outlines.single.xpToComplete, kDefaultXpToCompleteObjective);
    });

    test(
      'skips a course that fails to resolve, reporting it via onError',
      () async {
        final cache = JoinedObjectiveCache();
        final failed = <String>[];
        await cache.rebuild(
          ['ok', 'bad'],
          outlineOf: (u) async {
            if (u == 'bad') throw Exception('boom');
            return _outline(['lo-a']);
          },
          onError: (uuid, e, s) => failed.add(uuid),
        );
        expect(cache.ids, {'lo-a'});
        expect(cache.outlines.length, 1);
        // The failure is surfaced, not swallowed (a silently-empty cache is the
        // exact failure mode this guards against).
        expect(failed, ['bad']);
      },
    );

    test(
      'two rooms of one quest stay distinct entries, questId preserved (#8087)',
      () async {
        // The #8087 collapse happened upstream of rebuild (uuid-keyed maps in
        // rebuildFromJoinedCourses); this pins the contract that makes the
        // room-id keying work: each key gets its own entry with courseId = the
        // key, and the resolved outline's questId survives for band dedupe.
        final cache = JoinedObjectiveCache();
        await cache.rebuild(
          ['!r1:x', '!r2:x'],
          outlineOf: (roomId) async =>
              _outline(roomId == '!r1:x' ? ['lo-a'] : ['lo-b'], questId: 'q1'),
        );
        expect(cache.outlines.length, 2);
        expect(cache.outlines.map((o) => o.courseId).toSet(), {
          '!r1:x',
          '!r2:x',
        });
        expect(cache.outlines.map((o) => o.questId).toSet(), {'q1'});
      },
    );

    test('is empty with no joined courses', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild(const [], outlineOf: (u) async => _outline(['x']));
      expect(cache.ids, isEmpty);
      expect(cache.outlines, isEmpty);
    });
  });

  /// The cache reads each joined course as that course shows it: its own copy
  /// (content-studio) when a course admin sent one, else today's pins. Two
  /// rooms of one quest share one cached outline, so the copy must apply per
  /// course and never leak into the shared cache.
  group('JoinedObjectiveCache.rebuildFromJoinedCourses (course copy)', () {
    const questId = 'quest-1';
    late Client client;

    ActivityPlanModel plan(String id) => ActivityPlanModel(
      req: ActivityPlanRequest(
        topic: '',
        mode: '',
        objective: '',
        media: MediaEnum.nan,
        cefrLevel: LanguageLevelTypeEnum.a1,
        languageOfInstructions: 'en',
        targetLanguage: 'es',
        numberOfParticipants: 2,
      ),
      title: '',
      learningObjective: '',
      instructions: '',
      vocab: const [],
      activityId: id,
    );

    QuestOutline shared() {
      const los = ['lo-1', 'lo-2', 'lo-3'];
      const acts = {
        'lo-1': ['a1', 'a2'],
        'lo-2': ['b1'],
        'lo-3': ['c1'],
      };
      return QuestOutline(
        quest: QuestPlan(
          id: questId,
          name: '',
          description: '',
          targetLanguage: 'es',
          sequence: [
            for (final lo in los)
              QuestObjectiveStep(
                objective: LearningObjective(id: lo, objective: lo),
                wasMinted: false,
              ),
          ],
        ),
        groups: [
          for (final lo in los)
            QuestObjectiveGroup(
              objective: LearningObjective(id: lo, objective: lo),
              activities: [
                for (final a in acts[lo]!)
                  QuestActivity(activityId: a, plan: plan(a)),
              ],
            ),
        ],
      );
    }

    Room course(String id) {
      final room = Room(id: id, client: client, membership: Membership.join);
      putState(room, EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace});
      putPowerLevels(room);
      putState(
        room,
        PangeaEventTypes.coursePlan,
        CoursePlanEvent(uuid: questId, l2: 'es').toJson(),
      );
      client.rooms.add(room);
      return room;
    }

    setUp(() async {
      client = await getTestClient();
      final cached = shared();
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async =>
          Result.value(cached);
    });
    tearDown(() async {
      QuestRepo.debugBuildOutline = null;
      QuestRepo.resetOutlineCacheForTest();
      await client.dispose();
    });

    CourseLoOutline outlineOf(JoinedObjectiveCache cache, String roomId) =>
        cache.outlines.firstWhere((o) => o.courseId == roomId);

    test('a course with a copy reads it; its sibling without one reads the '
        'shared quest with its pins', () async {
      final withCopy = course('!copy:x');
      putCopy(withCopy, {
        'lo-3': ['c1'],
        'lo-1': ['a2'],
      });
      final withPins = course('!pins:x');
      putState(
        withPins,
        PangeaEventTypes.teacherMode,
        const TeacherModeModel(
          enabled: false,
          pinnedActivitiesByObjective: {
            'lo-1': ['a1'],
          },
        ).toJson(),
      );

      final cache = JoinedObjectiveCache();
      await cache.rebuildFromJoinedCourses(client);

      final copied = outlineOf(cache, '!copy:x');
      expect(copied.orderedLoIds, ['lo-3', 'lo-1']);
      expect(copied.activityIdsByLo, {
        'lo-3': {'c1'},
        'lo-1': {'a2'},
      });

      final pinned = outlineOf(cache, '!pins:x');
      expect(pinned.orderedLoIds, ['lo-1', 'lo-2', 'lo-3']);
      expect(pinned.activityIdsByLo['lo-1'], {'a1'});
    });

    test('a copy sent by a non-admin is ignored', () async {
      final room = course('!forged:x');
      putCopy(room, {
        'lo-2': ['b1'],
      }, sender: kStudent);

      final cache = JoinedObjectiveCache();
      await cache.rebuildFromJoinedCourses(client);

      expect(outlineOf(cache, '!forged:x').orderedLoIds, [
        'lo-1',
        'lo-2',
        'lo-3',
      ]);
    });
  });
}
