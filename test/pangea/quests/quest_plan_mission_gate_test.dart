import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// Regression: #9088. A quest with no Missions has no activities under it, so
/// it renders a "0 activities" card with nothing behind it. Browse listed those
/// cards while the preview refused the same rows, and the learner saw "Oops,
/// something went wrong" on every tap.
///
/// What is pinned here: the Mission gate is one rule applied wherever a course
/// plan is resolved, so the list and the detail page can never disagree about
/// whether a course exists.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('quest_mission_gate');
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
  });

  Map<String, dynamic> questRow(String id, {required int missions}) => {
    'id': id,
    'req': {'target_language': 'es', 'target_l1': 'en', 'target_cefr': 'A1'},
    'res': {
      'name': 'Cafe & Restaurant Ordering',
      'description': 'Order a coffee.',
      'learning_objective_sequence': List.generate(
        missions,
        (i) => {'id': 'lo-$i'},
      ),
    },
  };

  /// Serves every quest-plans read from [rows] while [body] runs — the
  /// collection endpoint as a page, the by-id endpoint as a single document.
  Future<void> withRows(
    List<Map<String, dynamic>> rows,
    Future<void> Function() body,
  ) => http.runWithClient(body, () {
    return MockClient((request) async {
      final path = request.url.path;
      final byId = RegExp(r'/quest-plans/([^/?]+)$').firstMatch(path);
      if (byId != null) {
        final id = byId.group(1);
        final row = rows.where((r) => r['id'] == id).firstOrNull;
        if (row == null) {
          return http.Response('{"errors":[{"message":"Not Found"}]}', 404);
        }
        return http.Response(jsonEncode(row), 200);
      }
      return http.Response(
        jsonEncode({
          'docs': rows,
          'totalDocs': rows.length,
          'limit': rows.length,
          'page': 1,
          'totalPages': 1,
          'hasNextPage': false,
          'hasPrevPage': false,
        }),
        200,
      );
    });
  });

  test('the browse list drops a quest with no Missions', () async {
    await withRows(
      [
        questRow('empty-quest', missions: 0),
        questRow('real-quest', missions: 3),
      ],
      () async {
        final plans = await QuestPlansRepo.getMany([
          'empty-quest',
          'real-quest',
        ]);
        expect(
          plans.keys,
          ['real-quest'],
          reason:
              'a Mission-less quest resolved into a browse card the preview '
              'then refused — the #9088 crash',
        );
        expect(plans['real-quest']!.topicIds, hasLength(3));
      },
    );
  });

  test('resolving one quest by id applies the same gate', () async {
    await withRows([questRow('empty-quest', missions: 0)], () async {
      expect(await QuestPlansRepo.get('empty-quest'), isNull);
    });

    await withRows([questRow('real-quest', missions: 1)], () async {
      expect((await QuestPlansRepo.get('real-quest'))!.uuid, 'real-quest');
    });
  });
}
