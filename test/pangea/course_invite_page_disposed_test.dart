import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/courses/own/invite/course_invite_page.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// CLIENT-EYE / CLIENT-EYF — the course invite page resolves its space id by
/// awaiting the creation completer and then a state sync, and the page is
/// routed away from while that wait is pending: the Invite button's own
/// `getSpaceId` call navigates on completion, and (until #9359 moved the
/// page's settings switches onto the create-course page) every switch's
/// FutureBuilder parked a lookup on the same completer. Each of those read
/// `Matrix.of(context)` after its await, and `State.context` on a disposed
/// State throws a null check — twelve times in one second on the reporting
/// device, once per rebuild that had created a future.
///
/// The page now resolves the client before it awaits. This disposes the page
/// mid-wait, completes the creation, and asserts the pending lookup still
/// resolves to the space id. Without the fix the lookup fails with the null
/// check, and the parked FutureBuilder futures fail the test as uncaught
/// errors.

class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const courseId = 'quest-plan-uuid';
  const roomId = '!course:fakeServer.notExisting';

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    // Avatar reads BotName.byEnvironment → Environment.botName, which needs
    // GetStorage (path_provider-backed) and dotenv to be readable.
    final tempDir = await Directory.systemTemp.createTemp('course_invite');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': 'pangeabot',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
        'CMS_API': 'https://cms.test',
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'test-token',
    );
    // initState loads the course plan. A verdict already in the removed cache
    // settles that load as "no longer available" before any CMS request, on
    // the real clock, so nothing of it outlives the pumped tree.
    await GetStorage.init('quest_removed_storage');
    QuestRepo.removedQuests.mark(courseId);
    await QuestRepo.removedQuests.load;
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  /// The created space, already carrying both state events `getSpaceId`
  /// would otherwise wait on, so the lookup resolves without a sync.
  void buildCourseSpace() {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    room.setState(
      Event(
        type: PangeaEventTypes.coursePlan,
        content: {'uuid': courseId, 'l2': 'es'},
        stateKey: '',
        senderId: userId,
        eventId: '\$coursePlan',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    room.setState(
      Event(
        type: PangeaEventTypes.courseSettings,
        content: {'require_analytics_access': false},
        stateKey: '',
        senderId: userId,
        eventId: '\$courseSettings',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    client.rooms.add(room);
  }

  testWidgets(
    'a space lookup pending when the page is disposed still resolves',
    (tester) async {
      buildCourseSpace();
      FakeMatrixApi.calledEndpoints.clear();
      final creation = Completer<String>();

      // Should the course-plan read reach the CMS anyway, answer it offline
      // rather than let a real request outlive the test.
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            _TestMatrix(
              clients: [client],
              store: store,
              child: MaterialApp(
                theme: ThemeData(
                  extensions: [PangeaColors.of(Brightness.light)],
                ),
                locale: const Locale('en'),
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                home: CourseInvitePage(
                  courseId,
                  courseCreationCompleter: creation,
                ),
              ),
            ),
          );
          // Bounded pumps, not pumpAndSettle: the course-loading spinner never
          // settles.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byType(CourseInvitePage), findsOneWidget);

          final page = tester.state<CourseInvitePageController>(
            find.byType(CourseInvitePage),
          );
          final pending = page.getSpaceId();

          // Route away while the creation is still pending.
          await tester.pumpWidget(const SizedBox());
          expect(find.byType(CourseInvitePage), findsNothing);

          creation.complete(roomId);
          expect(await pending, roomId);
          await tester.pump();
          // Drain the profile request the avatar issued while the page was
          // still up: the fake API answers on a timer, and the SDK keeps a
          // 30 s timer of its own around the fetch.
          await tester.pump(const Duration(seconds: 31));

          // Nothing on the page reads the room directory, before or after it
          // is gone.
          expect(
            FakeMatrixApi.calledEndpoints.keys.where(
              (path) => path.contains('/directory/list/room/'),
            ),
            isEmpty,
          );
        },
        () => MockClient(
          (_) async =>
              http.Response('{"errors":[{"message":"Not Found"}]}', 404),
        ),
      );
    },
  );
}
