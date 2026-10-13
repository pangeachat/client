import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/courses/add_course_tile.dart';
import 'package:fluffychat/routes/courses/find_course_page.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// The browse page shows the access pills and they narrow the list (#9358;
/// course-preview.instructions.md).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Client client;

  Map<String, dynamic> course(String roomId, String joinRule) => {
    'room_id': roomId,
    'name': roomId,
    'num_joined_members': 1,
    'world_readable': false,
    'guest_can_join': false,
    'join_rule': joinRule,
    'course_id': 'quest-$roomId',
  };

  Map<String, dynamic> questRow(String id) => {
    'id': id,
    'req': {'target_language': 'es', 'target_l1': 'en', 'target_cefr': 'A1'},
    'res': {
      'name': id,
      'description': '',
      'learning_objective_sequence': [
        {'learning_objective': 'lo-1'},
      ],
    },
  };

  /// Every quest-plans read resolves each id asked for to a one-Mission
  /// quest, by id or as a page.
  MockClient cms() => MockClient((request) async {
    final byId = RegExp(
      r'/quest-plans/([^/?]+)$',
    ).firstMatch(Uri.decodeFull(request.url.path));
    if (byId != null) {
      return http.Response(jsonEncode(questRow(byId.group(1)!)), 200);
    }
    final ids = RegExp(r'where\[id\]\[in\]\[\d+\]=([^&]+)')
        .allMatches(Uri.decodeFull(request.url.query))
        .map((m) => m.group(1)!)
        .toList();
    final docs = [for (final id in ids) questRow(id)];
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

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('find_course_page');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    await GetStorage.init('quest_removed_storage');
    dotenv.testLoad(
      mergeWith: {'CMS_API': 'https://cms.test', 'BOT_NAME': 'pangeabot'},
    );
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': 'es',
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
        ],
      }),
    });
    await PLanguageStore.initialize();

    client = Client(
      'find-course-page-test',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'chunk': [course('!open', 'public'), course('!ask', 'knock')],
            'next_batch': null,
          }),
          200,
        ),
      ),
      database: await MatrixSdkDatabase.init(
        'find-course-page-test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    client.homeserver = Uri.parse('https://matrix.test');
    client.bearerToken = 'syt_test';
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
  });

  tearDownAll(() => client.dispose());

  Iterable<String> tileTitles(WidgetTester tester) => tester
      .widgetList<AddCourseTile>(find.byType(AddCourseTile))
      .map(
        (tile) => tile.content.title(
          L10n.of(tester.element(find.byType(FindCoursePage))),
        ),
      );

  testWidgets('the pills show and narrow the list', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Provider<MatrixState>.value(
            value: _FakeMatrixState(client),
            child: const FindCoursePage(
              closeButton: SizedBox.shrink(),
              showAll: true,
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await settle();
      expect(find.widgetWithText(FilterChip, 'All'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Public'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Restricted'), findsOneWidget);
      expect(tileTitles(tester), unorderedEquals(['!open', '!ask']));

      await tester.tap(find.widgetWithText(FilterChip, 'Public'));
      await settle();
      expect(tileTitles(tester), ['!open']);

      await tester.tap(find.widgetWithText(FilterChip, 'Restricted'));
      await settle();
      expect(tileTitles(tester), ['!ask']);
    }, cms);
  });
}
