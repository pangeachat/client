import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/spaces/course_access_filter.dart';
import 'package:fluffychat/routes/courses/public_course_search_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// The browse list's access pills (#9358; course-preview.instructions.md).
/// The catalog does not filter by join rule, so the list does, over the pages
/// it fetches.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final tempDir = Directory.systemTemp.createTempSync('browse_access_filter');
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

  Map<String, dynamic> course(String roomId, String joinRule) => {
    'room_id': roomId,
    'name': roomId,
    'num_joined_members': 1,
    'world_readable': false,
    'guest_can_join': false,
    'join_rule': joinRule,
    'course_id': 'quest-$roomId',
  };

  /// Serves the CMS's quest-plans reads: a one-Mission quest for every id
  /// asked for, so every course the catalog returns can render a card. [hold]
  /// can delay a read until the test releases it.
  MockClient cms({Future<void> Function(List<String> ids)? hold}) =>
      MockClient((request) async {
        final ids = RegExp(r'where\[id\]\[in\]\[\d+\]=([^&]+)')
            .allMatches(Uri.decodeFull(request.url.query))
            .map((m) => m.group(1)!)
            .toList();
        await hold?.call(ids);
        final docs = ids
            .map(
              (id) => {
                'id': id,
                'req': {
                  'target_language': 'es',
                  'target_l1': 'en',
                  'target_cefr': 'A1',
                },
                'res': {
                  'name': id,
                  'description': '',
                  'learning_objective_sequence': [
                    {'id': 'lo-1'},
                  ],
                },
              },
            )
            .toList();
        return http.Response(
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
      });

  /// A client whose public-course catalog is [catalog]: each request's
  /// response, given its query parameters. No login and no rooms.
  Future<Client> clientServing(
    Future<Map<String, dynamic>> Function(Map<String, String> query) catalog,
  ) async {
    final client = Client(
      'browse-access-filter-test',
      httpClient: MockClient((request) async {
        expect(request.url.path, endsWith('/public_courses'));
        final body = await catalog(request.url.queryParameters);
        return http.Response(jsonEncode(body), 200);
      }),
      database: await MatrixSdkDatabase.init(
        'browse-access-filter-test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    client.homeserver = Uri.parse('https://matrix.test');
    client.bearerToken = 'syt_test';
    return client;
  }

  Future<void> settled(PublicCourseSearchController controller) async {
    for (var i = 0; i < 100 && controller.loadingMore.value; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.loadingMore.value, isFalse, reason: 'load never ended');
  }

  Future<void> drain() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<String> shown(PublicCourseSearchController controller) =>
      controller.loadedCourses.map((c) => c.room.roomId).toList();

  test('each pill narrows the list to its join rule', () async {
    await http.runWithClient(() async {
      final client = await clientServing(
        (_) async => {
          'chunk': [course('!open', 'public'), course('!ask', 'knock')],
          'next_batch': null,
        },
      );
      final controller = PublicCourseSearchController(client: client);
      controller.initCourseSearch();
      await settled(controller);
      expect(shown(controller), unorderedEquals(['!open', '!ask']));

      controller.setAccessFilter(CourseAccessFilter.public);
      await settled(controller);
      expect(shown(controller), ['!open']);

      controller.setAccessFilter(CourseAccessFilter.restricted);
      await settled(controller);
      expect(shown(controller), ['!ask']);

      controller.setAccessFilter(CourseAccessFilter.all);
      await settled(controller);
      expect(shown(controller), unorderedEquals(['!open', '!ask']));

      controller.disposeCourseSearch();
    }, cms);
  });

  test('a filter keeps paging until it finds a match', () async {
    await http.runWithClient(() async {
      final client = await clientServing(
        (query) async => switch (query['since']) {
          null => {
            'chunk': [course('!ask', 'knock')],
            'next_batch': 'page-2',
          },
          _ => {
            'chunk': [course('!open', 'public')],
            'next_batch': null,
          },
        },
      );
      final controller = PublicCourseSearchController(client: client)
        ..accessFilter.value = CourseAccessFilter.public;
      controller.initCourseSearch();
      await settled(controller);
      expect(shown(controller), ['!open']);
      controller.disposeCourseSearch();
    }, cms);
  });

  test(
    'a page answering the old filters never lands in the new list',
    () async {
      final spanishPage = Completer<void>();
      final frenchPlans = Completer<void>();
      final cursors = <String?>[];
      await http.runWithClient(
        () async {
          final client = await clientServing((query) async {
            final since = query['since'];
            cursors.add(since);
            if (query['target_language'] == 'es') {
              await spanishPage.future;
              return {
                'chunk': [course('!spanish', 'public')],
                'next_batch': 'spanish-page-2',
              };
            }
            if (since == null) {
              return {
                'chunk': [course('!french', 'public')],
                'next_batch': 'french-page-2',
              };
            }
            return {'chunk': [], 'next_batch': null};
          });
          final controller = PublicCourseSearchController(client: client)
            ..targetLanguageFilter.value = LanguageModel(
              langCode: 'es',
              displayName: 'es',
            );
          controller.initCourseSearch();
          await drain();

          // The learner switches language while the Spanish page is in flight.
          // The French load gets its first page and is resolving its plans when
          // the Spanish page finally answers.
          controller.setTargetLanguageFilter(
            LanguageModel(langCode: 'fr', displayName: 'fr'),
          );
          await drain();
          spanishPage.complete();
          await drain();
          frenchPlans.complete();
          await settled(controller);

          expect(shown(controller), ['!french']);
          expect(
            cursors,
            [null, null, 'french-page-2'],
            reason: "the Spanish page's cursor replaced the French load's",
          );
          controller.disposeCourseSearch();
        },
        () => cms(
          hold: (ids) async {
            if (ids.contains('quest-!french')) await frenchPlans.future;
          },
        ),
      );
    },
  );
}
