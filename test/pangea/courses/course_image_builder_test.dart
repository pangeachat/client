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
import 'package:fluffychat/pangea/common/widgets/course_image_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// #9264: a course room with no `m.room.avatar` shows its quest's cover, so a
/// room created before quests had covers stops showing a letter. An avatar the
/// admin set always wins, and a quest with no cover keeps the letter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('course_image_builder');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  const coverUrl = 'https://cdn.test/cover-thumb.png';

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

  /// Serves quest-plans by id from [rows] and the `media` collection with one
  /// row, `upload-1`. [statusFor] overrides the status of a quest read, to
  /// simulate a failure. Returns the list of quest ids read.
  Future<List<String>> withCms(
    List<Map<String, dynamic>> rows,
    Future<void> Function() body, {
    int Function(String questId)? statusFor,
  }) async {
    final reads = <String>[];
    await http.runWithClient(body, () {
      return MockClient((request) async {
        final path = request.url.path;
        final byId = RegExp(r'/quest-plans/([^/?]+)$').firstMatch(path);
        if (byId != null) {
          final id = byId.group(1)!;
          reads.add(id);
          final status = statusFor?.call(id) ?? 200;
          final row = rows.where((r) => r['id'] == id).firstOrNull;
          if (status != 200 || row == null) {
            return http.Response('{"errors":[]}', row == null ? 404 : status);
          }
          return http.Response(jsonEncode(row), 200);
        }
        if (path.endsWith('/media')) {
          return http.Response(
            jsonEncode({
              'docs': [
                {
                  'id': 'upload-1',
                  'url': 'https://cdn.test/cover.png',
                  'sizes': {
                    'thumbnail': {'url': coverUrl},
                  },
                },
              ],
              'totalDocs': 1,
              'limit': 1,
              'page': 1,
              'totalPages': 1,
              'hasNextPage': false,
              'hasPrevPage': false,
            }),
            200,
          );
        }
        return http.Response('unexpected ${request.url}', 500);
      });
    });
    return reads;
  }

  group('QuestPlansRepo.cover', () {
    test('resolves the quest image and reads it once', () async {
      final reads = await withCms(
        [questRow('q1', uploadId: 'upload-1')],
        () async {
          expect(await QuestPlansRepo.cover('q1'), Uri.parse(coverUrl));
          expect(await QuestPlansRepo.cover('q1'), Uri.parse(coverUrl));
        },
      );
      expect(reads, ['q1']);
      expect(QuestPlansRepo.cachedCover('q1'), Uri.parse(coverUrl));
    });

    test('a quest with no image, or a removed quest, has no cover', () async {
      final reads = await withCms([questRow('bare')], () async {
        expect(await QuestPlansRepo.cover('bare'), isNull);
        expect(await QuestPlansRepo.cover('gone'), isNull);
        expect(await QuestPlansRepo.cover('bare'), isNull);
        expect(await QuestPlansRepo.cover('gone'), isNull);
      });
      expect(reads, ['bare', 'gone'], reason: 'both answers are cached');
    });

    test('a failed read is not cached, so the next call retries', () async {
      var fail = true;
      final reads = await withCms(
        [questRow('q1', uploadId: 'upload-1')],
        () async {
          expect(await QuestPlansRepo.cover('q1'), isNull);
          fail = false;
          expect(await QuestPlansRepo.cover('q1'), Uri.parse(coverUrl));
        },
        statusFor: (_) => fail ? 500 : 200,
      );
      expect(reads, ['q1', 'q1']);
    });

    test('a quest-plans read seeds the cover, so no second read', () async {
      final reads = await withCms(
        [questRow('q1', uploadId: 'upload-1')],
        () async {
          await QuestPlansRepo.get('q1');
          expect(await QuestPlansRepo.cover('q1'), Uri.parse(coverUrl));
        },
      );
      expect(reads, ['q1']);
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
      late List<String> reads;
      await tester.runAsync(() async {
        reads = await withCms([questRow('q1', uploadId: 'upload-1')], () async {
          await tester.pumpWidget(builder(avatar: avatar, courseId: 'q1'));
        });
      });
      expect(find.text('$avatar'), findsOneWidget);
      expect(reads, isEmpty);
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
      expect(find.text(coverUrl), findsOneWidget);
    });

    testWidgets('a known cover paints on the first frame', (tester) async {
      await tester.runAsync(() async {
        await withCms([questRow('q1', uploadId: 'upload-1')], () async {
          await QuestPlansRepo.cover('q1');
        });
      });
      await tester.pumpWidget(builder(courseId: 'q1'));
      expect(find.text(coverUrl), findsOneWidget);
    });

    testWidgets('a room that is not a course keeps the letter', (tester) async {
      await tester.pumpWidget(builder());
      expect(find.text('letter'), findsOneWidget);
    });
  });
}
