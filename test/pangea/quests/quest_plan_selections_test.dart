import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../courses/course_missions_fixtures.dart';
import '../fake_pangea_controller.dart';

/// A quest entry's selected activities and note (org quests doc, "Each entry
/// in the Can-Do sequence"; pangeachat/.github#832). Per Can-Do, a course
/// shows its own copy's activities; without a copy, its pins; without pins
/// that name a listed activity, the plan's selection; without a selection
/// that names one, every activity. The plan's note shows where a copy's note
/// does, until the course has a copy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('quest_plan_selections');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  setUpAll(() async {
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'test-token',
    );
    dotenv.testLoad(mergeWith: {'CMS_API': 'https://cms.test'});
    await GetStorage.init('env_override');
    await GetStorage.init('quest_removed_storage');
  });

  setUp(() async {
    await GetStorage('quest_removed_storage').erase();
    QuestRepo.removedQuests = QuestRepo.newRemovedQuestsCache();
    QuestRepo.resetOutlineCacheForTest();
    QuestRepo.debugDisplayL1 = 'en';
  });

  tearDown(() => QuestRepo.debugDisplayL1 = null);

  group('parsing a plan entry', () {
    QuestObjectiveStep step(Map<String, dynamic> extra) =>
        QuestObjectiveStep.fromJson({'learning_objective': 'lo1', ...extra});

    test('keeps no selection apart from an empty one', () {
      expect(step({}).activityIds, isNull);
      expect(step({'activity_ids': null}).activityIds, isNull);
      expect(step({'activity_ids': []}).activityIds, isEmpty);
      expect(step({'activity_ids': []}).activityIds, isNotNull);
      expect(
        step({
          'activity_ids': ['a2', 'a1'],
        }).activityIds,
        ['a2', 'a1'],
      );
    });

    test('a blank note is no note', () {
      expect(step({'note': 'Unit 3'}).note, 'Unit 3');
      for (final note in [null, '', '   ']) {
        expect(step({'note': note}).note, isNull, reason: '$note');
      }
    });

    test('selections list only the entries that select something', () {
      final quest = QuestPlan.fromJson({
        'id': 'q1',
        'res': {
          'learning_objective_sequence': [
            {
              'learning_objective': 'lo1',
              'activity_ids': ['a2'],
            },
            {'learning_objective': 'lo2', 'activity_ids': []},
            {'learning_objective': 'lo3'},
          ],
        },
      });
      expect(quest.activitySelections, {
        'lo1': ['a2'],
      });
    });
  });

  group('effectivePinnedActivityIds', () {
    const available = {'a1', 'a2', 'a3'};

    test('pins win over the plan selection', () {
      expect(effectivePinnedActivityIds(available, ['a1'], selected: ['a2']), {
        'a1',
      });
    });

    test('stale or empty pins fall to the plan selection, in its order', () {
      for (final pinned in [
        null,
        <String>[],
        const ['gone'],
      ]) {
        expect(
          effectivePinnedActivityIds(
            available,
            pinned,
            selected: ['a3', 'gone', 'a1'],
          ).toList(),
          ['a3', 'a1'],
          reason: '$pinned',
        );
      }
    });

    test('a stale or empty selection falls to every activity', () {
      for (final selected in [
        null,
        <String>[],
        const ['gone'],
      ]) {
        expect(
          effectivePinnedActivityIds(available, null, selected: selected),
          available,
          reason: '$selected',
        );
      }
    });
  });

  Map<String, dynamic> planEntry(String id, List<String> refs) => {
    'plan': {
      'activity_id': id,
      'title': id,
      'user_id': '@teacher:test',
      'l2': 'es',
      'roles': [
        {'role_id': 'r1', 'name': 'r1'},
      ],
      'goals': [
        {
          'id': '$id-g1',
          'goal': 'g1',
          'role_ids': ['r1'],
        },
      ],
    },
    'version_id': 'v-$id',
    'learning_objective_refs': refs,
  };

  /// The quest row: `lo1` selects `a3` then `a1` and has a note; `lo2`
  /// stores an empty selection. The listing has three activities for `lo1`
  /// and two for `lo2`.
  Future<QuestOutline> servedOutline() => http.runWithClient(
    () async => (await QuestRepo.outline('q1')).result!,
    () => MockClient((request) async {
      if (request.url.path.endsWith('/quests/q1/activities')) {
        return http.Response(
          jsonEncode({
            'missions': [
              {'lo_id': 'lo1', 'objective': 'Can order.'},
              {'lo_id': 'lo2', 'objective': 'Can pay.'},
            ],
            'activities': [
              planEntry('a1', ['lo1']),
              planEntry('a2', ['lo1']),
              planEntry('a3', ['lo1']),
              planEntry('b1', ['lo2']),
              planEntry('b2', ['lo2']),
            ],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/quest-plans/q1')) {
        return http.Response(
          jsonEncode({
            'id': 'q1',
            'req': {'target_language': 'es', 'target_l1': 'en'},
            'res': {
              'name': 'Quest',
              'description': '',
              'learning_objective_sequence': [
                {
                  'learning_objective': 'lo1',
                  'activity_ids': ['a3', 'a1'],
                  'note': 'Textbook unit 3',
                },
                {'learning_objective': 'lo2', 'activity_ids': []},
              ],
            },
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    }),
  );

  List<String> shown(QuestOutline outline, String loId) => [
    for (final a
        in outline.groups.firstWhere((g) => g.objective.id == loId).activities)
      a.activityId,
  ];

  group('a course without its own copy', () {
    test(
      'the shared outline keeps every activity and carries the note',
      () async {
        final outline = await servedOutline();
        expect(shown(outline, 'lo1'), ['a1', 'a2', 'a3']);
        expect(outline.groups.first.pacing?.note, 'Textbook unit 3');
        expect(outline.groups.last.pacing, isNull);
      },
    );

    test('previews and courses without pins show the plan selection', () async {
      final outline = (await servedOutline()).forRules(CourseListRules.none);
      expect(shown(outline, 'lo1'), ['a3', 'a1']);
      // An empty selection shows every activity.
      expect(shown(outline, 'lo2'), ['b1', 'b2']);
      expect(outline.groups.first.pacing?.note, 'Textbook unit 3');
      expect(outline.toCourseLoOutline().activityIdsByLo['lo1'], {'a3', 'a1'});
    });

    test('pins win; a stale pin falls to the plan selection', () async {
      final source = await servedOutline();
      final pinned = source.forRules(
        const CourseListRules(
          pins: {
            'lo1': ['a2'],
          },
        ),
      );
      expect(shown(pinned, 'lo1'), ['a2']);
      final stale = source.forRules(
        const CourseListRules(
          pins: {
            'lo1': ['gone'],
          },
        ),
      );
      expect(shown(stale, 'lo1'), ['a3', 'a1']);
    });

    test('a new copy starts from the selection and the note', () async {
      final copy = CourseMissionsEvent.snapshotOf(
        (await servedOutline()).restrictedTo(null),
      );
      expect(copy.missions.first.activityIds, ['a3', 'a1']);
      expect(copy.missions.first.note, 'Textbook unit 3');
      expect(copy.missions.last.activityIds, ['b1', 'b2']);
      expect(copy.missions.last.note, isNull);
      // What it writes reads back as a valid copy.
      expect(CourseMissionsEvent.tryParse(copy.toJson()), isNotNull);
    });

    test('a note longer than a copy allows is left out of it', () {
      final long = 'x' * (CourseMissionsEvent.maxNoteLength + 1);
      final outline = QuestOutline(
        quest: QuestPlan.fromJson({'id': 'q1', 'res': {}}),
        groups: [
          QuestObjectiveGroup(
            objective: QuestObjectiveStep.fromJson({
              'learning_objective': 'lo1',
            }).objective,
            activities: const [],
            pacing: MissionPacing(note: long),
          ),
        ],
      );
      expect(
        CourseMissionsEvent.snapshotOf(outline).missions.single.note,
        isNull,
      );
      expect(CourseMissionsEvent.longNoteLoIds(outline), ['lo1']);
    });
  });

  group('a course with its own copy', () {
    test('shows the copy, never the plan selection or note', () async {
      final outline = (await servedOutline()).forRules(
        CourseListRules(
          missions: CourseMissionsEvent.tryParse(
            copyContent({
              'lo1': ['a2', 'a1'],
            }),
          ),
        ),
      );
      expect(shown(outline, 'lo1'), ['a2', 'a1']);
      expect(outline.groups.single.pacing, isNull);
    });
  });

  group('the course-scoped map', () {
    QuestActivityCard card(String id, String loId) =>
        QuestActivityCard.fromJson({
          'res': {
            'plan': {'activity_id': id},
          },
          'learningObjectiveRefs': [loId],
        });

    final cards = [card('a1', 'lo1'), card('a2', 'lo1'), card('b1', 'lo2')];
    List<String> ids(List<QuestActivityCard> cards) => [
      for (final c in cards) c.activityId,
    ];

    test('without pins shows the plan selection, failing open', () {
      expect(
        ids(
          restrictCardsForCourse(
            cards,
            CourseListRules.none,
            selections: {
              'lo1': ['a2'],
              'lo2': ['gone'],
            },
          ),
        ),
        ['a2', 'b1'],
      );
    });

    test('pins win over the plan selection', () {
      expect(
        ids(
          restrictCardsForCourse(
            cards,
            const CourseListRules(
              pins: {
                'lo1': ['a1'],
              },
            ),
            selections: {
              'lo1': ['a2'],
            },
          ),
        ),
        ['a1', 'b1'],
      );
    });
  });
}
