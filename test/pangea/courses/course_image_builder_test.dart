import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/course_image_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// The reads a test's CMS answered: quest-plans by id, quest-plans by a list
/// of ids, and media, each list read as the ids it named.
class _CmsReads {
  final byId = <String>[];
  final lists = <List<String>>[];
  final media = <List<String>>[];
}

/// #9264: a course room with no `m.room.avatar` shows its quest's cover, so a
/// room created before quests had covers stops showing a letter. An avatar the
/// admin set always wins, and a quest with no cover keeps the letter. #9569:
/// covers asked for together are read together.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('course_image_builder');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  const noResponse = 0;

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
    QuestPlansRepo.resetCoverCacheForTest();
  });

  /// The cover the CMS serves for a media row. Media URLs are cached for the
  /// whole run, so a test that counts media reads uses upload ids of its own.
  Uri thumbnailOf(String uploadId) =>
      Uri.parse('https://cdn.test/$uploadId-thumb.png');

  Map<String, dynamic> questRow(String id, {String? uploadId}) => {
    'id': id,
    'req': {'target_language': 'es', 'target_l1': 'en', 'target_cefr': 'A1'},
    'res': {
      'name': 'Quest',
      'description': 'A quest.',
      'learning_objective_sequence': [
        {'id': 'lo-0'},
      ],
    },
    if (uploadId != null) 'image': {'upload_id': uploadId},
  };

  http.Response page(List<Map<String, dynamic>> docs) => http.Response(
    jsonEncode({
      'docs': docs,
      'totalDocs': docs.length,
      'limit': docs.length,
      'page': 1,
      'totalPages': 1,
      'hasNextPage': false,
      'hasPrevPage': false,
    }),
    200,
  );

  /// The ids a list read names, in order: `where[id][in][0]`, `[1]`, ...
  List<String> listedIds(Uri url) => [
    for (var i = 0; url.queryParameters['where[id][in][$i]'] != null; i++)
      url.queryParameters['where[id][in][$i]']!,
  ];

  /// Serves quest-plans from [rows], by id and by a list of ids, and a media
  /// row for every `upload-` id. [legacyIds] maps a course-plan id from before
  /// quests to the quest a read by id resolves it to, as the CMS does; a list
  /// read never matches one. [statusFor] overrides the status of a quest-plans
  /// read naming that quest, and [mediaStatus] of a media read, to simulate a
  /// failure; [noResponse] means the read got no answer at all.
  Future<_CmsReads> withCms(
    List<Map<String, dynamic>> rows,
    Future<void> Function() body, {
    Map<String, String> legacyIds = const {},
    int Function(String questId)? statusFor,
    int mediaStatus = 200,
  }) async {
    final cms = _CmsReads();
    await http.runWithClient(body, () {
      return MockClient((request) async {
        final url = request.url;
        if (url.path.endsWith('/media')) {
          final ids = url.queryParameters['where[id][in]']!.split(',');
          cms.media.add(ids);
          if (mediaStatus != 200) {
            return http.Response('{"errors":[]}', mediaStatus);
          }
          return page([
            for (final id in ids.where((id) => id.startsWith('upload-')))
              {
                'id': id,
                'url': 'https://cdn.test/$id.png',
                'sizes': {
                  'thumbnail': {'url': '${thumbnailOf(id)}'},
                },
              },
          ]);
        }
        final byId = RegExp(r'/quest-plans/([^/?]+)$').firstMatch(url.path);
        if (byId == null && !url.path.endsWith('/quest-plans')) {
          return http.Response('unexpected $url', 500);
        }
        final ids = byId == null ? listedIds(url) : [byId.group(1)!];
        if (byId == null) {
          cms.lists.add(ids);
        } else {
          cms.byId.add(ids.single);
        }
        final status = ids
            .map((id) => statusFor?.call(id) ?? 200)
            .firstWhere((status) => status != 200, orElse: () => 200);
        if (status == noResponse) {
          throw http.ClientException('Connection closed', url);
        }
        if (status != 200) return http.Response('{"errors":[]}', status);
        if (byId == null) {
          return page(rows.where((row) => ids.contains(row['id'])).toList());
        }
        final id = legacyIds[ids.single] ?? ids.single;
        final row = rows.where((row) => row['id'] == id).firstOrNull;
        if (row == null) return http.Response('{"errors":[]}', 404);
        return http.Response(jsonEncode(row), 200);
      });
    });
    return cms;
  }

  group('QuestPlansRepo.cover', () {
    test('resolves the quest image and reads it once', () async {
      final cms = await withCms(
        [questRow('q1', uploadId: 'upload-1')],
        () async {
          expect(await QuestPlansRepo.cover('q1'), thumbnailOf('upload-1'));
          expect(await QuestPlansRepo.cover('q1'), thumbnailOf('upload-1'));
        },
      );
      expect(cms.lists, [
        ['q1'],
      ]);
      expect(cms.byId, isEmpty);
      expect(QuestPlansRepo.cachedCover('q1'), thumbnailOf('upload-1'));
    });

    test(
      'covers asked for together share one quest and one media read',
      () async {
        final cms = await withCms(
          [
            questRow('q1', uploadId: 'upload-a'),
            questRow('q2', uploadId: 'upload-b'),
            questRow('q3'),
          ],
          () async {
            final covers = await Future.wait(
              ['q1', 'q2', 'q3'].map(QuestPlansRepo.cover),
            );
            expect(covers, [
              thumbnailOf('upload-a'),
              thumbnailOf('upload-b'),
              null,
            ]);
          },
        );
        expect(cms.lists, [
          ['q1', 'q2', 'q3'],
        ]);
        expect(cms.media, [
          ['upload-a', 'upload-b'],
        ]);
        expect(cms.byId, isEmpty);
      },
    );

    test('a quest with no image, or a removed quest, has no cover', () async {
      final cms = await withCms([questRow('bare')], () async {
        expect(await QuestPlansRepo.cover('bare'), isNull);
        expect(await QuestPlansRepo.cover('gone'), isNull);
        expect(await QuestPlansRepo.cover('bare'), isNull);
        expect(await QuestPlansRepo.cover('gone'), isNull);
      });
      expect(cms.lists, [
        ['bare'],
        ['gone'],
      ], reason: 'both answers are cached');
      expect(cms.byId, ['gone'], reason: 'only a read by id confirms removal');
      expect(await QuestRepo.removedQuests.contains('gone'), isTrue);
    });

    // A course made before quests names a course-plan id, which the CMS maps
    // to its quest on a read by id only. Taking its absence from a list read
    // as removal would lose the cover and mark a live course removed.
    test('a course-plan id from before quests is read by id', () async {
      final cms = await withCms(
        [questRow('quest-1', uploadId: 'upload-1')],
        () async {
          expect(
            await QuestPlansRepo.cover('course-plan-1'),
            thumbnailOf('upload-1'),
          );
        },
        legacyIds: {'course-plan-1': 'quest-1'},
      );
      expect(cms.lists, [
        ['course-plan-1'],
      ]);
      expect(cms.byId, ['course-plan-1']);
      expect(await QuestRepo.removedQuests.contains('course-plan-1'), isFalse);
    });

    // #9569: retrying a failed read on every mount sent a burst of reads at
    // a CMS that was already slow. A failure is read once per session.
    test('a failed read is reported and read once per quest', () async {
      final cms = await withCms(
        [
          questRow('q-500', uploadId: 'upload-1'),
          questRow('q-silent', uploadId: 'upload-1'),
        ],
        () async {
          for (var i = 0; i < 3; i++) {
            expect(await QuestPlansRepo.cover('q-500'), isNull);
            expect(await QuestPlansRepo.cover('q-silent'), isNull);
          }
        },
        statusFor: (id) => id == 'q-500' ? 500 : noResponse,
      );
      expect(cms.lists, [
        ['q-500'],
        ['q-silent'],
      ]);
      expect(cms.byId, isEmpty);
      expect(QuestPlansRepo.cachedCover('q-500'), isNull);
      expect(
        ErrorHandler.reportedOnceKeysForTest,
        containsAll(['quest-cover:q-500', 'quest-cover:q-silent']),
      );
    });

    test('a failed read fails every quest it named, reported once', () async {
      final cms = await withCms(
        [questRow('f1', uploadId: 'upload-1'), questRow('f2')],
        () async {
          for (var i = 0; i < 2; i++) {
            final covers = await Future.wait(
              ['f1', 'f2'].map(QuestPlansRepo.cover),
            );
            expect(covers, [null, null]);
          }
        },
        statusFor: (_) => 503,
      );
      expect(cms.lists, [
        ['f1', 'f2'],
      ]);
      expect(cms.byId, isEmpty);
      expect(
        ErrorHandler.reportedOnceKeysForTest,
        contains('quest-cover:f1,f2'),
      );
    });

    test('a failed media read is not read again', () async {
      final cms = await withCms(
        [questRow('m1', uploadId: 'upload-m1'), questRow('m2')],
        () async {
          for (var i = 0; i < 2; i++) {
            final covers = await Future.wait(
              ['m1', 'm2'].map(QuestPlansRepo.cover),
            );
            expect(covers, [null, null]);
          }
        },
        mediaStatus: 500,
      );
      expect(cms.lists, [
        ['m1', 'm2'],
      ]);
      expect(cms.media, [
        ['upload-m1'],
      ]);
    });

    test('a quest-plans read after a failure brings the cover back', () async {
      var fail = true;
      final cms = await withCms(
        [questRow('q1', uploadId: 'upload-1')],
        () async {
          expect(await QuestPlansRepo.cover('q1'), isNull);
          fail = false;
          // Opening the course's page reads its quest-plans row.
          await QuestPlansRepo.get('q1');
          expect(await QuestPlansRepo.cover('q1'), thumbnailOf('upload-1'));
        },
        statusFor: (_) => fail ? 500 : 200,
      );
      expect(cms.lists, [
        ['q1'],
      ], reason: 'the cover read');
      expect(cms.byId, ['q1'], reason: 'the page read');
      expect(QuestPlansRepo.cachedCover('q1'), thumbnailOf('upload-1'));
    });

    test('a quest-plans read seeds the cover, so no second read', () async {
      final cms = await withCms(
        [questRow('q1', uploadId: 'upload-1')],
        () async {
          await QuestPlansRepo.get('q1');
          expect(await QuestPlansRepo.cover('q1'), thumbnailOf('upload-1'));
        },
      );
      expect(cms.byId, ['q1']);
      expect(cms.lists, isEmpty);
    });
  });

  group('CourseImageBuilder', () {
    Widget builder({Uri? avatar, String? courseId}) => Directionality(
      textDirection: TextDirection.ltr,
      child: CourseImageBuilder(
        avatar: avatar,
        courseId: courseId,
        builder: (context, image) => Text('${image ?? 'letter'}'),
      ),
    );

    testWidgets('an admin-set avatar wins, and reads no quest', (tester) async {
      final avatar = Uri.parse('mxc://server/admin-set');
      late _CmsReads cms;
      await tester.runAsync(() async {
        cms = await withCms([questRow('q1', uploadId: 'upload-1')], () async {
          await tester.pumpWidget(builder(avatar: avatar, courseId: 'q1'));
        });
      });
      expect(find.text('$avatar'), findsOneWidget);
      expect(cms.lists, isEmpty);
      expect(cms.byId, isEmpty);
    });

    testWidgets('no avatar shows the quest cover once it loads', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await withCms([questRow('q1', uploadId: 'upload-1')], () async {
          await tester.pumpWidget(builder(courseId: 'q1'));
          expect(find.text('letter'), findsOneWidget);
          await QuestPlansRepo.cover('q1');
        });
      });
      await tester.pump();
      expect(find.text('${thumbnailOf('upload-1')}'), findsOneWidget);
    });

    testWidgets('avatars built in one frame share one read', (tester) async {
      const courseIds = ['q1', 'q2', 'q3'];
      late _CmsReads cms;
      await tester.runAsync(() async {
        cms = await withCms(
          [for (final id in courseIds) questRow(id, uploadId: 'upload-1')],
          () async {
            await tester.pumpWidget(
              Column(
                children: [for (final id in courseIds) builder(courseId: id)],
              ),
            );
            await Future.wait(courseIds.map(QuestPlansRepo.cover));
          },
        );
      });
      await tester.pump();
      expect(find.text('${thumbnailOf('upload-1')}'), findsNWidgets(3));
      expect(cms.lists, [courseIds]);
      expect(cms.byId, isEmpty);
    });

    testWidgets('a failed cover is not read again when the avatar remounts', (
      tester,
    ) async {
      late _CmsReads cms;
      await tester.runAsync(() async {
        cms = await withCms([questRow('q1', uploadId: 'upload-1')], () async {
          for (var i = 0; i < 3; i++) {
            await tester.pumpWidget(builder(courseId: 'q1'));
            await QuestPlansRepo.cover('q1');
            await tester.pumpWidget(const SizedBox());
          }
          await tester.pumpWidget(builder(courseId: 'q1'));
        }, statusFor: (_) => 503);
      });
      await tester.pump();
      expect(find.text('letter'), findsOneWidget);
      expect(cms.lists, [
        ['q1'],
      ]);
      expect(cms.byId, isEmpty);
    });

    testWidgets('a known cover paints on the first frame', (tester) async {
      await tester.runAsync(() async {
        await withCms([questRow('q1', uploadId: 'upload-1')], () async {
          await QuestPlansRepo.cover('q1');
        });
      });
      await tester.pumpWidget(builder(courseId: 'q1'));
      expect(find.text('${thumbnailOf('upload-1')}'), findsOneWidget);
    });

    testWidgets('a room that is not a course keeps the letter', (tester) async {
      await tester.pumpWidget(builder());
      expect(find.text('letter'), findsOneWidget);
    });
  });
}
