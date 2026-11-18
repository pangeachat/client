import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/not_started_session_controller.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../activity_session_fixtures.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// #9647 — a discussion opened by its activity address (a link, a reload, or
/// going back to the start page). A learner with a seat in the course's room,
/// ended or not, goes straight to the chat; anyone else gets the start page
/// (activities.instructions.md, "Discussions").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // GetStorage writes through path_provider, which has no implementation on
  // the test host.
  final tempDir = Directory.systemTemp.createTempSync('discussion_start_page');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  const otherCourseId = '!otherCourse:fakeServer.notExisting';
  final ended = DateTime.utc(2026, 1, 1, 13);

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    dotenv.testLoad(
      mergeWith: {
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
        'BOT_NAME': testDiscussionBotId,
      },
    );
    await GetStorage.init('env_override');
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
  });

  setUp(() async {
    client = await getTestClient();
    MatrixState.pangeaController = FakePangeaController(client: client);
  });

  tearDown(() async => client.dispose());

  /// The learner's course, with the discussion's room linked into it as the
  /// server links every room it makes for a discussion.
  Room courseSpace() {
    final space = Room(
      id: testDiscussionCourseId,
      client: client,
      membership: Membership.join,
    );
    space.setState(
      activitySessionStateEvent(
        space,
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
      ),
    );
    space.setState(
      activitySessionStateEvent(
        space,
        type: PangeaEventTypes.coursePlan,
        content: CoursePlanEvent(uuid: 'quest', l2: 'es').toJson(),
      ),
    );
    space.setState(
      activitySessionStateEvent(
        space,
        type: EventTypes.SpaceChild,
        stateKey: testDiscussionRoomId,
        content: {
          'via': ['fakeServer.notExisting'],
        },
      ),
    );
    return space;
  }

  /// Puts the course and the discussion's room, holding [seats], in the
  /// learner's rooms. The room belongs to [roomCourseId].
  void seedRooms({
    required List<ActivityRoleModel> seats,
    String roomCourseId = testDiscussionCourseId,
  }) => client.rooms.addAll([
    courseSpace(),
    discussionRoom(client, courseId: roomCourseId, seats: seats),
  ]);

  /// Opens the discussion's start page by its address, in the course unless
  /// [inCourse] is false (the app's own link names no course), and runs a
  /// second of frames. The page never settles: its plan, which has no server
  /// here, stays loading.
  Future<GoRouter> openStartPage(
    WidgetTester tester, {
    bool inCourse = true,
  }) async {
    final courseId = inCourse ? testDiscussionCourseId : null;
    final router = GoRouter(
      initialLocation: courseId == null
          ? WorkspaceNav.openActivity(Uri.parse('/'), testSessionActivityId)
          : WorkspaceNav.openCourseActivity(courseId, testSessionActivityId),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => ActivitySessionStartPage(
            activityId: testSessionActivityId,
            parentId: courseId,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The page that decides where the address leads did mount.
    expect(find.byType(NotStartedSession), findsOneWidget);
    return router;
  }

  Uri location(GoRouter router) => router.routeInformationProvider.value.uri;

  void expectChat(GoRouter router) {
    expect(activeRoomIdFromPanels(location(router)), testDiscussionRoomId);
    expect(activityInfoFor(location(router)), isNull);
  }

  void expectStartPage(GoRouter router) {
    expect(activeRoomIdFromPanels(location(router)), isNull);
    expect(
      activityInfoFor(location(router))?.activityId,
      testSessionActivityId,
    );
  }

  testWidgets('a learner who ended their seat goes straight to the chat', (
    tester,
  ) async {
    seedRooms(
      seats: [
        discussionSeat(testSessionUserId, finishedAt: ended, archivedAt: ended),
      ],
    );
    expectChat(await openStartPage(tester));
  });

  testWidgets('a learner still in the discussion goes straight to the chat', (
    tester,
  ) async {
    seedRooms(seats: [discussionSeat(testSessionUserId)]);
    expectChat(await openStartPage(tester));
  });

  testWidgets('a learner in the room without a seat gets the start page', (
    tester,
  ) async {
    seedRooms(seats: [discussionSeat('@classmate:fakeServer.notExisting')]);
    expectStartPage(await openStartPage(tester));
  });

  testWidgets('a seat in another course\'s room never opens this course\'s '
      'discussion', (tester) async {
    seedRooms(
      roomCourseId: otherCourseId,
      seats: [
        discussionSeat(testSessionUserId, finishedAt: ended, archivedAt: ended),
      ],
    );
    expectStartPage(await openStartPage(tester));
  });

  testWidgets('opened outside a course, a learner with a seat goes straight '
      'to the chat', (tester) async {
    seedRooms(
      seats: [
        discussionSeat(testSessionUserId, finishedAt: ended, archivedAt: ended),
      ],
    );
    expectChat(await openStartPage(tester, inCourse: false));
  });

  testWidgets('opened outside a course, a learner with no seat gets the '
      'start page', (tester) async {
    seedRooms(seats: [discussionSeat('@classmate:fakeServer.notExisting')]);
    expectStartPage(await openStartPage(tester, inCourse: false));
  });
}

/// Skips `initMatrix()`: the page reads the client and the analytics service
/// back out of the tree, nothing else.
class _TestMatrixState extends MatrixState {
  final AnalyticsDataService _service = _FakeAnalyticsDataService();

  @override
  // ignore: must_call_super
  void initState() {}

  @override
  AnalyticsDataService get analyticsDataService => _service;
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

class _FakeAnalyticsDataService implements AnalyticsDataService {
  @override
  late final AnalyticsUpdateDispatcher updateDispatcher =
      AnalyticsUpdateDispatcher(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
