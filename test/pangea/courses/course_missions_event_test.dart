import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../get_test_client.dart';
import 'course_missions_fixtures.dart';

/// The course's own copy (content-studio.instructions.md): parsed strictly,
/// counted only when a course admin sent it, snapshotted from the shown list
/// at creation, and applied to the course-scoped map's markers.
void main() {
  group('CourseMissionsEvent.tryParse', () {
    Map<String, dynamic> valid() => copyContent(
      {
        'lo-b': ['b1'],
        'lo-a': ['a1', 'a2'],
      },
      revision: 3,
      timeZone: 'America/New_York',
      notes: {'lo-b': 'Lesson 6'},
      dueAt: {'lo-b': '2026-10-20T21:00:00Z'},
    );

    test('reads a valid copy in its order', () {
      final copy = CourseMissionsEvent.tryParse(valid())!;
      expect(copy.revision, 3);
      expect(copy.timeZone, 'America/New_York');
      expect(copy.missions.map((m) => m.loId), ['lo-b', 'lo-a']);
      expect(copy.missions.first.note, 'Lesson 6');
      expect(copy.missions.first.dueAt, DateTime.utc(2026, 10, 20, 21));
      expect(copy.missions.last.activityIds, ['a1', 'a2']);
    });

    test('round-trips through toJson', () {
      final copy = CourseMissionsEvent.tryParse(valid())!;
      final again = CourseMissionsEvent.tryParse(copy.toJson())!;
      expect(again.toJson(), copy.toJson());
      expect(again.missions.first.dueAt, DateTime.utc(2026, 10, 20, 21));
    });

    final invalid = <String, Map<String, dynamic> Function()>{
      'version 2': () => valid()..['version'] = 2,
      'revision 0': () => valid()..['revision'] = 0,
      'revision as a string': () => valid()..['revision'] = '3',
      'missions missing': () => valid()..remove('missions'),
      'time zone not a string': () => valid()..['time_zone'] = 5,
      'a duplicate Can-Do': () => copyContent({'lo-a': []})
        ..['missions'] = [
          {'lo_id': 'lo-a', 'activity_ids': <String>[]},
          {'lo_id': 'lo-a', 'activity_ids': <String>[]},
        ],
      'a non-string activity id': () =>
          copyContent({'lo-a': []})
            ..['missions'] = [
              {
                'lo_id': 'lo-a',
                'activity_ids': ['a1', 2],
              },
            ],
      'an empty Can-Do id': () => copyContent({'': []}),
      'a 281-character note': () =>
          copyContent({'lo-a': []}, notes: {'lo-a': 'x' * 281}),
      'an unreadable due date': () =>
          copyContent({'lo-a': []}, dueAt: {'lo-a': 'next tuesday'}),
      'a due date with no offset (not an instant)': () =>
          copyContent({'lo-a': []}, dueAt: {'lo-a': '2026-10-20T21:00:00'}),
      'a date-only due date': () =>
          copyContent({'lo-a': []}, dueAt: {'lo-a': '2026-10-20'}),
    };
    for (final entry in invalid.entries) {
      test('rejects ${entry.key}', () {
        expect(CourseMissionsEvent.tryParse(entry.value()), isNull);
      });
    }

    test('accepts a due date with an explicit offset', () {
      expect(
        CourseMissionsEvent.tryParse(
          copyContent(
            {'lo-a': []},
            dueAt: {'lo-a': '2026-10-20T17:00:00-04:00'},
          ),
        )!.missions.single.dueAt,
        DateTime.utc(2026, 10, 20, 21),
      );
    });

    test('accepts a 280-character note', () {
      expect(
        CourseMissionsEvent.tryParse(
          copyContent({'lo-a': []}, notes: {'lo-a': 'x' * 280}),
        ),
        isNotNull,
      );
    });
  });

  group('room.courseMissions', () {
    late Client client;
    late Room room;

    setUp(() async {
      client = await getTestClient();
      room = Room(
        id: '!course:fakeServer.notExisting',
        client: client,
        membership: Membership.join,
      );
      putPowerLevels(room);
    });
    tearDown(() => client.dispose());

    test('counts a copy a course admin sent', () {
      putCopy(room, {
        'lo-a': ['a1'],
      });
      expect(room.courseMissions?.missions.single.loId, 'lo-a');
      expect(room.courseListRules.revision, 1);
    });

    test('ignores a copy a non-admin sent — a student cannot forge it', () {
      putCopy(room, {
        'lo-a': ['a1'],
      }, sender: kStudent);
      expect(room.courseMissions, isNull);
      expect(room.courseListRules.revision, 0);
    });

    test('ignores a copy whose sender lost admin since', () {
      putCopy(room, {
        'lo-a': ['a1'],
      });
      putState(room, EventTypes.RoomPowerLevels, {
        'users': {kTeacher: 50},
      });
      expect(room.courseMissions, isNull);
    });

    test('no copy reads as none', () {
      expect(room.courseMissions, isNull);
    });
  });

  test('new course spaces require power level 100 to send the copy', () {
    final events =
        RoomDefaults.defaultSpacePowerLevelsContent()['events'] as Map;
    expect(events[PangeaEventTypes.courseMissions], 100);
  });

  group('CourseMissionsEvent.snapshotOf (creation copy)', () {
    test('matches the shown outline: every Can-Do in order, its activities, '
        'revision 1, no time zone', () {
      QuestObjectiveGroup group(String lo, List<String> ids) =>
          QuestObjectiveGroup(
            objective: LearningObjective(id: lo, objective: lo),
            activities: [
              for (final id in ids)
                QuestActivity(activityId: id, plan: _plan(id)),
            ],
          );
      final outline = QuestOutline(
        quest: const QuestPlan(
          id: 'q1',
          name: '',
          description: '',
          targetLanguage: 'es',
          sequence: [],
        ),
        groups: [
          group('lo-2', ['b1', 'b2']),
          group('lo-1', ['a1']),
          group('lo-3', []),
        ],
      );
      final json = CourseMissionsEvent.snapshotOf(outline).toJson();
      expect(json, {
        'version': 1,
        'revision': 1,
        'missions': [
          {
            'lo_id': 'lo-2',
            'activity_ids': ['b1', 'b2'],
          },
          {
            'lo_id': 'lo-1',
            'activity_ids': ['a1'],
          },
          {'lo_id': 'lo-3', 'activity_ids': <String>[]},
        ],
      });
      // And it reads back as a valid copy.
      expect(CourseMissionsEvent.tryParse(json), isNotNull);
    });
  });

  /// Attaching a plan to an existing space writes the course's own copy —
  /// only when the actor is a course admin, and from the list the course
  /// shows without one (so this space's pins apply).
  group('addCourseToSpace writes the copy (attach to an existing space)', () {
    const self = '@test:fakeServer.notExisting';
    // The one room id the fake homeserver accepts state writes for.
    const spaceId = '!1234:fakeServer.notExisting';
    late Client client;

    /// The course rooms each outline read was scoped to (null = unscoped).
    late List<String?> outlineReads;

    /// What the outline read answers; null = a failed read.
    QuestOutline? Function(String? courseRoomId)? answer;

    setUp(() async {
      client = await getTestClient();
      FakeMatrixApi.calledEndpoints.clear();
      QuestRepo.resetOutlineCacheForTest();
      QuestRepo.debugDisplayL1 = 'en';
      outlineReads = [];
      answer = null;
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
        outlineReads.add(courseRoomId);
        final outline = answer?.call(courseRoomId);
        return outline == null
            ? Result<QuestOutline>.error('boom')
            : Result.value(outline);
      };
    });
    tearDown(() {
      QuestRepo.debugBuildOutline = null;
      QuestRepo.debugDisplayL1 = null;
      QuestRepo.resetOutlineCacheForTest();
      client.dispose();
    });

    Room space({required int ownLevel, String planId = 'q1'}) {
      final room = Room(
        id: spaceId,
        client: client,
        membership: Membership.join,
      );
      putState(room, EventTypes.RoomPowerLevels, {
        'users': {self: ownLevel},
        'events': {'m.space.child': 0},
      }, sender: self);
      // Already on this plan, so only the copy is left to write.
      putState(
        room,
        PangeaEventTypes.coursePlan,
        CoursePlanEvent(uuid: planId, l2: 'es').toJson(),
        sender: self,
      );
      putState(room, PangeaEventTypes.teacherMode, {
        'enabled': false,
        'pinned_activities_by_objective': {
          'lo-1': ['a1'],
        },
      }, sender: self);
      client.rooms.add(room);
      return room;
    }

    QuestOutline shown() => QuestOutline(
      quest: const QuestPlan(
        id: 'q1',
        name: '',
        description: '',
        targetLanguage: 'es',
        sequence: [],
      ),
      groups: [
        QuestObjectiveGroup(
          objective: const LearningObjective(id: 'lo-1', objective: ''),
          activities: [
            QuestActivity(activityId: 'a1', plan: _plan('a1')),
            QuestActivity(activityId: 'a2', plan: _plan('a2')),
          ],
        ),
        QuestObjectiveGroup(
          objective: const LearningObjective(id: 'lo-2', objective: ''),
          activities: [QuestActivity(activityId: 'b1', plan: _plan('b1'))],
        ),
      ],
    );

    List<dynamic> copyWrites() => [
      for (final e in FakeMatrixApi.calledEndpoints.entries)
        if (e.key.contains('/state/${PangeaEventTypes.courseMissions}'))
          ...e.value,
    ];

    test('an admin writes the snapshot, pins applied, revision 1', () async {
      answer = (_) => shown();
      await space(ownLevel: 100).addCourseToSpace('q1', targetLanguage: 'es');
      final writes = copyWrites();
      expect(writes, hasLength(1));
      expect(jsonDecode(writes.single as String), {
        'version': 1,
        'revision': 1,
        'missions': [
          {
            'lo_id': 'lo-1',
            'activity_ids': ['a1'],
          },
          {
            'lo_id': 'lo-2',
            'activity_ids': ['b1'],
          },
        ],
      });
    });

    test('a non-admin writes nothing', () async {
      answer = (_) => shown();
      await space(ownLevel: 50).addCourseToSpace('q1', targetLanguage: 'es');
      expect(copyWrites(), isEmpty);
    });

    test('the snapshot is the list this course shows its members: read '
        'through the course-scoped listing, so the quest owner\'s private '
        'activities stay in the copy', () async {
      // The course-scoped read also returns 'p1', a private activity of the
      // quest owner; an unscoped read (a preview) would not.
      answer = (courseRoomId) {
        final base = shown();
        if (courseRoomId != spaceId) return base;
        return QuestOutline(
          quest: base.quest,
          groups: [
            base.groups[0],
            QuestObjectiveGroup(
              objective: base.groups[1].objective,
              activities: [
                ...base.groups[1].activities,
                QuestActivity(activityId: 'p1', plan: _plan('p1')),
              ],
            ),
          ],
        );
      };
      await space(ownLevel: 100).addCourseToSpace('q1', targetLanguage: 'es');
      expect(outlineReads, [spaceId]);
      final written = jsonDecode(copyWrites().single as String) as Map;
      expect((written['missions'] as List)[1], {
        'lo_id': 'lo-2',
        'activity_ids': ['b1', 'p1'],
      });
    });

    /// Replaces the plan on a space whose copy names the old quest's Can-Dos,
    /// answering the plan write's wait-for-sync the way the server would.
    Future<void> replacePlan(Room room, {bool withOutline = true}) async {
      answer = withOutline ? (_) => shown() : null;
      final attach = room.addCourseToSpace('q1', targetLanguage: 'es');
      var done = false;
      unawaited(attach.whenComplete(() => done = true));
      for (var i = 0; i < 100 && !done; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        client.onSync.add(
          SyncUpdate(
            nextBatch: 'plan-$i',
            rooms: RoomsUpdate(join: {spaceId: JoinedRoomUpdate()}),
          ),
        );
        client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
      }
      await attach;
    }

    test('replacing the plan writes a fresh snapshot of the new quest at the '
        'old revision + 1 — never the old quest\'s copy', () async {
      final room = space(ownLevel: 100, planId: 'q0');
      putState(
        room,
        PangeaEventTypes.courseMissions,
        copyContent({
          'old-lo': ['old-a'],
        }, revision: 3),
        sender: self,
      );
      await replacePlan(room);
      final writes = copyWrites();
      expect(writes, hasLength(1));
      final written = jsonDecode(writes.single as String) as Map;
      expect(written['revision'], 4);
      expect(
        [for (final m in written['missions'] as List) (m as Map)['lo_id']],
        ['lo-1', 'lo-2'],
      );
    });

    test(
      'replacing the plan with no snapshot to hand clears the old '
      'quest\'s copy, so readers fall back to the new shared quest',
      () async {
        final room = space(ownLevel: 100, planId: 'q0');
        putState(
          room,
          PangeaEventTypes.courseMissions,
          copyContent({
            'old-lo': ['old-a'],
          }, revision: 3),
          sender: self,
        );
        await replacePlan(room, withOutline: false);
        final writes = copyWrites();
        expect(writes, hasLength(1));
        expect(jsonDecode(writes.single as String), <String, dynamic>{});
        // And an empty record reads as no copy.
        expect(CourseMissionsEvent.tryParse(<String, dynamic>{}), isNull);
      },
    );

    test('replacing the plan when the outline read throws still clears '
        'the old quest\'s copy', () async {
      final room = space(ownLevel: 100, planId: 'q0');
      putState(
        room,
        PangeaEventTypes.courseMissions,
        copyContent({
          'old-lo': ['old-a'],
        }, revision: 3),
        sender: self,
      );
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async =>
          throw StateError('boom');
      await replacePlan(room, withOutline: false);
      expect(jsonDecode(copyWrites().single as String), <String, dynamic>{});
    });

    test('replacing the plan with no snapshot and no old copy writes '
        'nothing', () async {
      await replacePlan(space(ownLevel: 100, planId: 'q0'), withOutline: false);
      expect(copyWrites(), isEmpty);
    });

    test(
      're-attaching the same plan with no snapshot keeps the copy',
      () async {
        final room = space(ownLevel: 100);
        putState(
          room,
          PangeaEventTypes.courseMissions,
          copyContent({
            'lo-2': ['b1'],
          }),
          sender: self,
        );
        await room.addCourseToSpace('q1', targetLanguage: 'es');
        expect(copyWrites(), isEmpty);
      },
    );

    test('a non-admin replacing the plan writes no copy (today)', () async {
      final room = space(ownLevel: 50, planId: 'q0');
      await replacePlan(room);
      expect(copyWrites(), isEmpty);
      expect(
        FakeMatrixApi.calledEndpoints.keys.where(
          (k) => k.contains('/state/${PangeaEventTypes.coursePlan}'),
        ),
        isNotEmpty,
        reason: 'the plan itself is still written, as today',
      );
    });

    test('an existing copy for the same plan is left alone', () async {
      final room = space(ownLevel: 100);
      putState(
        room,
        PangeaEventTypes.courseMissions,
        copyContent({
          'lo-2': ['b1'],
        }),
        sender: self,
      );
      answer = (_) => shown();
      await room.addCourseToSpace('q1', targetLanguage: 'es');
      expect(copyWrites(), isEmpty);
    });
  });

  /// A new course's copy is read through the course-scoped listing right
  /// after the space exists, waiting briefly; it never blocks creation.
  group('courseScopedOutline (creation and attach snapshots)', () {
    QuestOutline outlineFor(String id) => QuestOutline(
      quest: QuestPlan(
        id: id,
        name: '',
        description: '',
        targetLanguage: 'es',
        sequence: const [],
      ),
      groups: const [],
    );

    setUp(() {
      QuestRepo.resetOutlineCacheForTest();
      QuestRepo.debugDisplayL1 = 'en';
    });
    tearDown(() {
      QuestRepo.debugBuildOutline = null;
      QuestRepo.debugDisplayL1 = null;
      QuestRepo.resetOutlineCacheForTest();
    });

    test(
      'reads for the course and joins that course\'s read in flight',
      () async {
        final pending = Completer<Result<QuestOutline>>();
        final scopes = <String?>[];
        QuestRepo.debugBuildOutline = (id, {courseRoomId}) {
          scopes.add(courseRoomId);
          return pending.future;
        };
        final pageLoad = QuestRepo.outline('q1', courseRoomId: '!c:x');
        final snapshot = courseScopedOutline('q1', '!c:x');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        pending.complete(Result.value(outlineFor('q1')));
        expect((await snapshot)?.quest.id, 'q1');
        await pageLoad;
        expect(scopes, ['!c:x']);
      },
    );

    test('gives up at the cap', () async {
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) =>
          Completer<Result<QuestOutline>>().future;
      expect(
        await courseScopedOutline(
          'q1',
          '!c:x',
          cap: const Duration(milliseconds: 50),
        ),
        isNull,
      );
    });

    test('a failed read is no outline', () async {
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async =>
          Result<QuestOutline>.error('boom');
      expect(await courseScopedOutline('q1', '!c:x'), isNull);
    });

    test('a read that throws is no outline, never an error', () async {
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async =>
          throw StateError('boom');
      expect(await courseScopedOutline('q1', '!c:x'), isNull);
    });
  });

  /// The creator writes the new course's copy once the space exists.
  group('writeNewCourseCopy (creation)', () {
    const self = '@test:fakeServer.notExisting';
    const spaceId = '!1234:fakeServer.notExisting';
    late Client client;
    late List<String?> scopes;

    QuestOutline outline({bool withPrivate = false}) => QuestOutline(
      quest: const QuestPlan(
        id: 'q1',
        name: '',
        description: '',
        targetLanguage: 'es',
        sequence: [],
      ),
      groups: [
        QuestObjectiveGroup(
          objective: const LearningObjective(id: 'lo-1', objective: ''),
          activities: [
            QuestActivity(activityId: 'a1', plan: _plan('a1')),
            if (withPrivate) QuestActivity(activityId: 'p1', plan: _plan('p1')),
          ],
        ),
      ],
    );

    setUp(() async {
      client = await getTestClient();
      FakeMatrixApi.calledEndpoints.clear();
      QuestRepo.resetOutlineCacheForTest();
      QuestRepo.debugDisplayL1 = 'en';
      scopes = [];
      QuestRepo.debugBuildOutline = (id, {courseRoomId}) async {
        scopes.add(courseRoomId);
        // Only a read scoped to the course carries the owner's private one.
        return Result.value(outline(withPrivate: courseRoomId == spaceId));
      };
    });
    tearDown(() {
      QuestRepo.debugBuildOutline = null;
      QuestRepo.debugDisplayL1 = null;
      QuestRepo.resetOutlineCacheForTest();
      client.dispose();
    });

    Room newSpace({int ownLevel = 100}) {
      final room = Room(
        id: spaceId,
        client: client,
        membership: Membership.join,
      );
      putState(room, EventTypes.RoomPowerLevels, {
        'users': {self: ownLevel},
      }, sender: self);
      putState(
        room,
        PangeaEventTypes.coursePlan,
        CoursePlanEvent(uuid: 'q1', l2: 'es').toJson(),
        sender: self,
      );
      client.rooms.add(room);
      return room;
    }

    List<dynamic> copyWrites() => [
      for (final e in FakeMatrixApi.calledEndpoints.entries)
        if (e.key.contains('/state/${PangeaEventTypes.courseMissions}'))
          ...e.value,
    ];

    test('writes revision 1 from the course-scoped list, the quest owner\'s '
        'private activity included', () async {
      await newSpace().writeNewCourseCopy('q1');
      expect(scopes, [spaceId]);
      expect(jsonDecode(copyWrites().single as String), {
        'version': 1,
        'revision': 1,
        'missions': [
          {
            'lo_id': 'lo-1',
            'activity_ids': ['a1', 'p1'],
          },
        ],
      });
    });

    test('writes from the quest it was created with, before the space\'s '
        'plan event is readable (a just-created space may hold only its '
        'create event)', () async {
      final room = Room(
        id: spaceId,
        client: client,
        membership: Membership.join,
      );
      putState(room, EventTypes.RoomPowerLevels, {
        'users': {self: 100},
      }, sender: self);
      client.rooms.add(room);
      await room.writeNewCourseCopy('q1');
      expect(scopes, [spaceId]);
      expect(copyWrites(), hasLength(1));
    });

    test(
      'a failed read writes nothing (the course reads the shared quest)',
      () async {
        QuestRepo.debugBuildOutline = (id, {courseRoomId}) async =>
            Result<QuestOutline>.error('boom');
        await newSpace().writeNewCourseCopy('q1');
        expect(copyWrites(), isEmpty);
      },
    );

    test(
      'a non-admin, or a course that already has a copy, writes nothing',
      () async {
        await newSpace(ownLevel: 50).writeNewCourseCopy('q1');
        expect(copyWrites(), isEmpty);
        final room = newSpace();
        putCopy(room, {
          'lo-1': ['a1'],
        }, sender: self);
        await room.writeNewCourseCopy('q1');
        expect(copyWrites(), isEmpty);
      },
    );
  });

  group('restrictCardsForCourse (course-scoped map markers)', () {
    QuestActivityCard card(String id, List<String> los) =>
        QuestActivityCard.fromJson({
          'res': {
            'plan': {'activity_id': id},
          },
          'learningObjectiveRefs': los,
        });
    final cards = [
      card('a1', ['lo-a']),
      card('a2', ['lo-a']),
      card('b1', ['lo-b']),
      card('c1', ['lo-c']),
    ];
    List<String> ids(List<QuestActivityCard> cs) =>
        cs.map((c) => c.activityId).toList();

    test("a copy keeps only each listed Can-Do's activities", () {
      final copy = CourseMissionsEvent.tryParse(
        copyContent({
          'lo-b': ['b1'],
          'lo-a': ['a2'],
        }),
      );
      expect(
        ids(restrictCardsForCourse(cards, CourseListRules(missions: copy))),
        ['a2', 'b1'],
      );
    });

    test('no copy is exactly today: the fail-open pin rule', () {
      const pins = CourseListRules(
        pins: {
          'lo-a': ['a1'],
          'lo-b': ['gone'],
        },
      );
      expect(ids(restrictCardsForCourse(cards, pins)), ['a1', 'b1', 'c1']);
      expect(ids(restrictCardsForCourse(cards, CourseListRules.none)), [
        'a1',
        'a2',
        'b1',
        'c1',
      ]);
    });
  });
}

ActivityPlanModel _plan(String id) => ActivityPlanModel(
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
