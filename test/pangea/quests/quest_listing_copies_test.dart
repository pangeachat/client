import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// The course listing with the course's own copies (Content Studio v2): a
/// member's read asks for them (`include_course_copies`, `extra_lo_ids`), the
/// per-activity `family_ids` come back into the outline, and a Can-Do the
/// record added beyond the quest is shown from the listing's own missions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('quest_listing_copies');
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

  Map<String, dynamic> planEntry(
    String id, {
    required List<String> refs,
    List<String>? family,
  }) => {
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
    'family_ids': ?family,
  };

  /// Serves the quest row (Can-Do `lo1` only) and the choreo listing [body],
  /// recording each listing request's query.
  Future<T> serving<T>(
    Map<String, dynamic> body,
    List<Uri> listingRequests,
    Future<T> Function() run, {
    Map<String, dynamic> Function(Uri request)? bodyFor,
  }) => http.runWithClient(run, () {
    return MockClient((request) async {
      if (request.url.path.endsWith('/quests/q1/activities')) {
        listingRequests.add(request.url);
        return http.Response(
          jsonEncode(bodyFor?.call(request.url) ?? body),
          200,
        );
      }
      if (request.url.path.endsWith('/quest-plans/q1')) {
        return http.Response(
          jsonEncode({
            'id': 'q1',
            'req': {
              'target_language': 'es',
              'target_l1': 'en',
              'target_cefr': 'A1',
            },
            'res': {
              'name': 'Quest',
              'description': '',
              'learning_objective_sequence': [
                {'learning_objective': 'lo1'},
              ],
            },
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
  });

  Map<String, dynamic> listing() => {
    'missions': [
      {'lo_id': 'lo1', 'objective': 'Can order.'},
      {'lo_id': 'lo-added', 'objective': 'Can pay.'},
    ],
    'activities': [
      planEntry('a1', refs: ['lo1'], family: ['a1', 'c1']),
      planEntry('c1', refs: ['lo1'], family: ['a1', 'c1']),
      planEntry('p1', refs: ['lo-added']),
    ],
  };

  group('extraLoIdsFor', () {
    test('keeps only Can-Dos the quest does not carry, in a stable order', () {
      expect(
        QuestRepo.extraLoIdsFor({'lo2', 'lo1', 'lo-b', 'lo-a'}, ['lo1', 'lo2']),
        ['lo-a', 'lo-b'],
      );
    });

    test('is empty when the quest carries every Can-Do', () {
      expect(QuestRepo.extraLoIdsFor({'lo1'}, ['lo1']), isEmpty);
    });
  });

  test('a member read asks for copies and the added Can-Dos', () async {
    final requests = <Uri>[];
    await serving(listing(), requests, () async {
      await QuestRepo.outline(
        'q1',
        courseRoomId: '!room:test',
        courseLoIds: {'lo1', 'lo-added', 'lo-gone'},
        copyRevision: 4,
      );
    });
    expect(requests, hasLength(1));
    final query = requests.single.queryParametersAll;
    expect(query['course_room_id'], ['!room:test']);
    expect(query['include_course_copies'], ['1']);
    expect(query['extra_lo_ids'], ['lo-added', 'lo-gone']);
  });

  test('more extra Can-Dos than one read accepts are read in batches and '
      'merged, none dropped', () async {
    final extras = [
      for (var i = 0; i < 40; i++) 'x${i.toString().padLeft(2, '0')}',
    ];
    final requests = <Uri>[];
    // Each read answers only for the Can-Dos it was asked about.
    Map<String, dynamic> answer(Uri request) {
      final asked = request.queryParametersAll['extra_lo_ids'] ?? const [];
      return {
        'missions': [
          for (final id in asked) {'lo_id': id, 'objective': id},
        ],
        'activities': [
          for (final id in asked) planEntry('p-$id', refs: [id]),
        ],
      };
    }

    final outline = await serving(const {}, requests, () async {
      return (await QuestRepo.outline(
        'q1',
        courseRoomId: '!room:test',
        courseLoIds: extras.toSet(),
        copyRevision: 1,
      )).result!;
    }, bodyFor: answer);
    final asked = [
      for (final r in requests)
        r.queryParametersAll['extra_lo_ids'] ?? const <String>[],
    ];
    expect(asked.map((a) => a.length), [
      QuestRepo.extraLoIdsPerRead,
      40 - QuestRepo.extraLoIdsPerRead,
    ]);
    expect([...asked[0], ...asked[1]], extras);
    expect(
      outline.addedGroups.map((g) => g.objective.id).toSet(),
      extras.toSet(),
    );
    expect(
      outline.addedGroups
          .expand((g) => g.activities)
          .map((a) => a.activityId)
          .toSet(),
      {for (final id in extras) 'p-$id'},
    );
  });

  test('a read outside a course asks for neither', () async {
    final requests = <Uri>[];
    await serving(listing(), requests, () async {
      await QuestRepo.outline('q1');
    });
    final query = requests.single.queryParametersAll;
    expect(query.containsKey('include_course_copies'), isFalse);
    expect(query.containsKey('extra_lo_ids'), isFalse);
    expect(query.containsKey('course_room_id'), isFalse);
  });

  test('a course with no record asks for no extras', () async {
    final requests = <Uri>[];
    await serving(listing(), requests, () async {
      await QuestRepo.outline('q1', courseRoomId: '!room:test');
    });
    final query = requests.single.queryParametersAll;
    expect(query['include_course_copies'], ['1']);
    expect(query.containsKey('extra_lo_ids'), isFalse);
  });

  test('family ids and the added Can-Do come back into the outline', () async {
    final requests = <Uri>[];
    final outline = await serving(listing(), requests, () async {
      return (await QuestRepo.outline(
        'q1',
        courseRoomId: '!room:test',
        courseLoIds: {'lo1', 'lo-added'},
        copyRevision: 1,
      )).result!;
    });
    expect(outline.familyIdsByActivity, {
      'a1': ['a1', 'c1'],
      'c1': ['a1', 'c1'],
    });
    // The shared quest's own list is untouched by the added Can-Do.
    expect(outline.groups.map((g) => g.objective.id), ['lo1']);
    expect(outline.addedGroups.map((g) => g.objective.id), ['lo-added']);
    expect(outline.addedGroups.single.activities.map((a) => a.activityId), [
      'p1',
    ]);
  });

  test('forRules shows the record, not every listed copy, and the added '
      'Can-Do', () async {
    final requests = <Uri>[];
    final outline = await serving(listing(), requests, () async {
      return (await QuestRepo.outline(
        'q1',
        courseRoomId: '!room:test',
        courseLoIds: {'lo1', 'lo-added'},
        copyRevision: 1,
      )).result!;
    });
    final copy = CourseMissionsEvent.tryParse({
      'version': 1,
      'revision': 1,
      'missions': [
        {
          'lo_id': 'lo1',
          'activity_ids': ['c1'],
          'removed_activity_ids': ['a1'],
        },
        {
          'lo_id': 'lo-added',
          'activity_ids': ['p1'],
        },
      ],
    })!;
    final shown = outline.forRules(CourseListRules(missions: copy));
    expect(
      {
        for (final g in shown.groups)
          g.objective.id: g.activities.map((a) => a.activityId).toList(),
      },
      {
        'lo1': ['c1'],
        'lo-added': ['p1'],
      },
    );
    expect(shown.quest.learningObjectiveIds, ['lo1', 'lo-added']);
    // The original is hidden but its stars still reach the copy.
    expect(shown.credit.canonicalOf('a1'), 'c1');
  });

  test('a new record revision misses the cached listing', () async {
    final requests = <Uri>[];
    await serving(listing(), requests, () async {
      await QuestRepo.outline('q1', courseRoomId: '!r', copyRevision: 1);
      await QuestRepo.outline('q1', courseRoomId: '!r', copyRevision: 1);
      expect(requests, hasLength(1));
      await QuestRepo.outline('q1', courseRoomId: '!r', copyRevision: 2);
      expect(requests, hasLength(2));
    });
  });
}
