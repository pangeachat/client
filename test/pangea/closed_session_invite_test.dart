import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/notifications/notification_tap_utils.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/chat_list/chat_invite_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'activity_session_fixtures.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';
import 'sentry_capture_harness.dart';

/// #9798 — an invite to an activity session stays open after the session
/// fills or finishes, and is never withdrawn. So opening one says the session
/// is over, and the learner can clear it with one Dismiss, or still go in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Before ActivityPlanRepo is touched: its cache reaches for path_provider
  // when it is built.
  final tempDir = Directory.systemTemp.createTempSync('closed_session_invite');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  const ana = '@ana:fakeServer.notExisting';
  const ben = '@ben:fakeServer.notExisting';

  /// Holds every seat, played by members still in the room.
  final fullPreview = _preview(
    seats: [_seat('r1', ana), _seat('r2', ben)],
    members: {ana: 'join', ben: 'join'},
  );

  /// Every player finished or left. The seat Ben left is open on paper, so
  /// counting seats alone would offer it.
  final finishedPreview = _preview(
    seats: [_seat('r1', ana, finished: true), _seat('r2', ben)],
    members: {ana: 'join', ben: 'leave'},
  );

  /// One of the two seats is still free.
  final openPreview = _preview(
    seats: [_seat('r1', ana)],
    members: {ana: 'join'},
  );

  late _InviteServer server;
  late Client client;
  late Room room;
  late SharedPreferences store;
  late SentryCaptureHarness sentry;

  setUpAll(() async {
    dotenv.testLoad(
      mergeWith: {
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
        'CHOREO_API': 'https://choreo.test',
        'BOT_NAME': '@bot:fakeServer.notExisting',
      },
    );
    await GetStorage.init('env_override');
    await GetStorage.init('activity_plan_storage');
    // The page's avatars go through the image cache's database.
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    // Born on the real clock: a repo's one-shot cache init created inside one
    // test's fake clock never completes for the next test.
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'test-token',
    );
    await ActivityPlanRepo.instance.clearCache();
    sentry = SentryCaptureHarness();
    await sentry.init();
  });

  tearDownAll(() async => sentry.close());

  setUp(() async {
    server = _InviteServer();
    client = await getTestClient(httpClient: server);
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'test-token',
      client: client,
    );
    ActivityPlanRepo.instance.resetForTesting();
    RoomSummaryResponse.referencePlanResolver = (_) => twoRoleActivityPlan();
    room = _invitedRoom(client, sender: ana);
    client.rooms.add(room);
  });

  tearDown(() async {
    RoomSummaryResponse.referencePlanResolver =
        RoomSummaryResponse.defaultReferencePlanResolver;
    await client.dispose();
  });

  /// Runs frames with the real clock turning between them, because a client
  /// built in setUp reads its responses on the real clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The learner's join coming back from the server in a sync.
  Future<void> syncJoin(WidgetTester tester) async {
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'after_join',
          rooms: RoomsUpdate(
            join: {
              testSessionRoomId: JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [
                    MatrixEvent(
                      type: EventTypes.RoomMember,
                      content: {'membership': 'join'},
                      senderId: testSessionUserId,
                      stateKey: testSessionUserId,
                      eventId: '\$joined',
                      originServerTs: DateTime.utc(2026, 1, 1, 13),
                    ),
                  ],
                ),
              ),
            },
          ),
        ),
      ),
    );
    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
    await settle(tester);
  }

  group('the chat list prompt', () {
    /// The result each answered prompt returned to its caller.
    late List<bool> answers;

    setUp(() => answers = []);

    Future<void> tapInvite(WidgetTester tester, {Room? invite}) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => answers.add(
                  await ChatInviteDialog.show(context, invite ?? room),
                ),
                child: const Text('invite row'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('invite row'));
      await settle(tester);
    }

    L10n l10n(WidgetTester tester) =>
        L10n.of(tester.element(find.byType(Scaffold).first));

    void expectClosedPrompt(WidgetTester tester, String notice) {
      expect(find.text(notice), findsOneWidget);
      expect(find.text(l10n(tester).dismiss), findsOneWidget);
      expect(find.text(l10n(tester).openChat), findsOneWidget);
      expect(find.text(l10n(tester).accept), findsNothing);
      expect(find.text(l10n(tester).decline), findsNothing);
      expect(find.text(l10n(tester).block), findsNothing);
    }

    void expectNormalPrompt(WidgetTester tester) {
      expect(find.text(l10n(tester).accept), findsOneWidget);
      expect(find.text(l10n(tester).decline), findsOneWidget);
      expect(find.text(l10n(tester).block), findsOneWidget);
      expect(find.text(l10n(tester).dismiss), findsNothing);
    }

    testWidgets('a full session says so, and Dismiss declines the invite', (
      tester,
    ) async {
      server.preview = fullPreview;
      await tapInvite(tester);
      expectClosedPrompt(tester, l10n(tester).sessionFull);

      await tester.tap(find.text(l10n(tester).dismiss));
      await settle(tester);

      expect(server.memberships, ['leave']);
      expect(answers, [false]);
    });

    testWidgets('a finished session says so, even with a seat open on paper, '
        'and Dismiss declines the invite', (tester) async {
      server.preview = finishedPreview;
      await tapInvite(tester);
      expectClosedPrompt(tester, l10n(tester).sessionFinished);

      await tester.tap(find.text(l10n(tester).dismiss));
      await settle(tester);

      expect(server.memberships, ['leave']);
      expect(answers, [false]);
    });

    testWidgets('someone invited on purpose can still go in', (tester) async {
      server.preview = fullPreview;
      await tapInvite(tester);

      await tester.tap(find.text(l10n(tester).openChat));
      await settle(tester);
      expect(server.memberships, ['join']);

      await syncJoin(tester);
      expect(answers, [true]);
    });

    testWidgets('closing the prompt leaves the invite alone', (tester) async {
      server.preview = fullPreview;
      await tapInvite(tester);

      await tester.tapAt(Offset.zero);
      await settle(tester);

      expect(find.text(l10n(tester).dismiss), findsNothing);
      expect(server.memberships, isEmpty);
      expect(answers, [false]);
    });

    testWidgets('an open session keeps the normal prompt', (tester) async {
      server.preview = openPreview;
      await tapInvite(tester);
      expectNormalPrompt(tester);
    });

    testWidgets('a failed preview keeps the normal prompt and is reported', (
      tester,
    ) async {
      server.previewStatus = 500;
      final reportedBefore = sentry.events.length;
      await tapInvite(tester);

      expect(server.previewReads, 1);
      expectNormalPrompt(tester);
      expect(
        sentry.events.skip(reportedBefore).map((e) => e.throwable),
        contains(isA<PangeaHttpException>()),
      );
    });

    testWidgets('a preview that has no room keeps the normal prompt and is '
        'reported', (tester) async {
      server.preview = const {};
      final reportedBefore = sentry.events.length;
      await tapInvite(tester);

      expect(server.previewReads, 1);
      expectNormalPrompt(tester);
      expect(sentry.events.length, greaterThan(reportedBefore));
    });

    testWidgets('seats that cannot be counted keep the normal prompt', (
      tester,
    ) async {
      // The plan never hydrates: nothing says how many seats there are.
      RoomSummaryResponse.referencePlanResolver = (_) => null;
      server.preview = fullPreview;
      await tapInvite(tester);
      expectNormalPrompt(tester);
    });

    testWidgets('a thin plan is fetched before the seats are counted', (
      tester,
    ) async {
      RoomSummaryResponse.referencePlanResolver =
          RoomSummaryResponse.defaultReferencePlanResolver;
      server.preview = fullPreview;
      await http.runWithClient(() => tapInvite(tester), _planServer);

      expectClosedPrompt(tester, l10n(tester).sessionFull);
      // The repo writes the fetched plan to disk on a timer.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a second tap during the read shows one prompt', (
      tester,
    ) async {
      server.preview = fullPreview;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    answers.add(await ChatInviteDialog.show(context, room)),
                child: const Text('invite row'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('invite row'));
      await tester.tap(find.text('invite row'));
      await settle(tester);

      expect(server.previewReads, 1);
      expect(find.text(l10n(tester).dismiss), findsOneWidget);
    });

    testWidgets('an invite to a discussion keeps the normal prompt', (
      tester,
    ) async {
      // A discussion is entered through Join, never an invite, and has no
      // seats to fill: the server made the room, and marked it.
      final discussion = Room(
        id: '!discussion:fakeServer.notExisting',
        client: client,
        membership: Membership.invite,
      );
      discussion.setState(
        Event(
          type: EventTypes.RoomCreate,
          content: {
            'type': '${PangeaRoomTypes.activitySession}:$testSessionActivityId',
            'pangea.discussion': {
              'course_id': '!course:fakeServer.notExisting',
              'activity_id': testSessionActivityId,
            },
          },
          stateKey: '',
          senderId: '@bot:fakeServer.notExisting',
          eventId: '\$discussion',
          originServerTs: DateTime.utc(2026, 1, 1, 12),
          room: discussion,
        ),
      );
      client.rooms.add(discussion);
      server.preview = fullPreview;
      await tapInvite(tester, invite: discussion);

      expect(server.previewReads, 0);
      expectNormalPrompt(tester);
    });

    testWidgets('an invite to an ordinary chat reads no preview', (
      tester,
    ) async {
      final chat = Room(
        id: '!chat:fakeServer.notExisting',
        client: client,
        membership: Membership.invite,
      );
      client.rooms.add(chat);
      await tapInvite(tester, invite: chat);

      expect(server.previewReads, 0);
      expectNormalPrompt(tester);
    });
  });

  group('the activity page a push or an email opens', () {
    Future<GoRouter> pumpStartPage(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: client.activitySessionLocation(
          Uri.parse('/'),
          sessionRoomId: testSessionRoomId,
          activityId: testSessionActivityId,
        ),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const ActivitySessionStartPage(
              activityId: testSessionActivityId,
              roomId: testSessionRoomId,
              parentId: null,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      // The page starts only once the localizations load on a later frame,
      // so its first read needs those frames inside the mock too.
      await http.runWithClient(() async {
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
        await settle(tester);
      }, _planServer);
      return router;
    }

    L10n l10n(WidgetTester tester) =>
        L10n.of(tester.element(find.byType(ActivitySessionStartPage)));

    List<PanelTypesEnum> leftPanels(GoRouter router) => parseOpenPanels(
      router.routeInformationProvider.value.uri,
    ).left.map((t) => t.type).toList();

    /// The page's taller content scrolls, and buttons sit in a footer below
    /// it, so a frame this size shows them whatever the content's height.
    void useTallWindow(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// Ends with the frames that run out the timers the page starts: the
    /// image cache's ten-second cleanup and the one-second limit on room-state
    /// rebuilds.
    void pageTest(String description, WidgetTesterCallback body) =>
        testWidgets(description, (tester) async {
          await body(tester);
          await tester.pump(const Duration(seconds: 11));
        });

    void expectClosedPage(WidgetTester tester, String notice) {
      expect(find.text(notice), findsOneWidget);
      expect(find.text(l10n(tester).dismiss), findsOneWidget);
      expect(find.text(l10n(tester).openChat), findsOneWidget);
      expect(find.text(l10n(tester).confirm), findsNothing);
    }

    pageTest('a full session says so, and Dismiss declines and leaves', (
      tester,
    ) async {
      useTallWindow(tester);
      server.preview = fullPreview;
      final router = await pumpStartPage(tester);
      expectClosedPage(tester, l10n(tester).sessionFull);
      expect(leftPanels(router), [PanelTypesEnum.activity]);

      await tester.tap(find.text(l10n(tester).dismiss));
      await settle(tester);

      expect(server.memberships, ['leave']);
      expect(leftPanels(router), isEmpty);
    });

    pageTest('a finished session says so instead of offering the seat a '
        'player left', (tester) async {
      useTallWindow(tester);
      server.preview = finishedPreview;
      await pumpStartPage(tester);
      expectClosedPage(tester, l10n(tester).sessionFinished);
    });

    pageTest('someone invited on purpose can still go in', (tester) async {
      useTallWindow(tester);
      server.preview = fullPreview;
      final router = await pumpStartPage(tester);

      await tester.tap(find.text(l10n(tester).openChat));
      await settle(tester);
      expect(server.memberships, ['join']);

      await syncJoin(tester);
      expect(leftPanels(router), [PanelTypesEnum.room]);
    });

    pageTest('the minimized phone sheet still says why', (tester) async {
      tester.view.physicalSize = const Size(375, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      server.preview = fullPreview;
      await pumpStartPage(tester);

      expect(find.text(l10n(tester).sessionFull), findsOneWidget);
      expect(find.text(l10n(tester).dismiss), findsOneWidget);
      expect(find.text(l10n(tester).openChat), findsOneWidget);
    });

    pageTest('nothing is offered until the preview says a seat is left', (
      tester,
    ) async {
      useTallWindow(tester);
      server.preview = fullPreview;
      // Made here, not in setUp: completing a future from outside the test's
      // fake clock would never wake the request waiting on it.
      final previewArrives = Completer<void>();
      server.previewHeldUntil = previewArrives.future;
      await pumpStartPage(tester);

      expect(find.text(l10n(tester).confirm), findsNothing);
      expect(find.text(l10n(tester).dismiss), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      previewArrives.complete();
      await settle(tester);
      expectClosedPage(tester, l10n(tester).sessionFull);
    });

    pageTest('an open session keeps the role picker', (tester) async {
      useTallWindow(tester);
      server.preview = openPreview;
      await pumpStartPage(tester);

      expect(find.text(l10n(tester).confirm), findsOneWidget);
      expect(find.text(l10n(tester).dismiss), findsNothing);
    });

    pageTest('a failed preview keeps the role picker and is reported', (
      tester,
    ) async {
      useTallWindow(tester);
      server.previewStatus = 500;
      final reportedBefore = sentry.events.length;
      await pumpStartPage(tester);

      expect(server.previewReads, greaterThan(0));
      expect(find.text(l10n(tester).confirm), findsOneWidget);
      expect(find.text(l10n(tester).dismiss), findsNothing);
      expect(
        sentry.events.skip(reportedBefore).map((e) => e.throwable),
        contains(isA<PangeaHttpException>()),
      );
    });

    pageTest('a full session with no invite keeps its return button', (
      tester,
    ) async {
      useTallWindow(tester);
      client.rooms.remove(room);
      server.preview = fullPreview;
      await pumpStartPage(tester);

      expect(find.text(l10n(tester).sessionFull), findsOneWidget);
      expect(find.text(l10n(tester).returnHome), findsOneWidget);
      expect(find.text(l10n(tester).dismiss), findsNothing);
    });
  });
}

ActivityRoleModel _seat(String id, String userId, {bool finished = false}) =>
    ActivityRoleModel(
      id: id,
      userId: userId,
      role: id,
      finishedAt: finished ? DateTime.utc(2026, 1, 1, 13) : null,
    );

/// What room_preview answers for a v3 session: a thin plan reference, the
/// role state, and the membership of whoever holds a role.
Map<String, dynamic> _preview({
  required List<ActivityRoleModel> seats,
  required Map<String, String> members,
}) => {
  PangeaEventTypes.activityPlan: {
    'default': {
      'content': {'activity_id': testSessionActivityId, 'version_id': 'v1'},
    },
  },
  PangeaEventTypes.activityRole: {
    'default': {
      'content': ActivityRolesModel({
        for (final seat in seats) seat.id: seat,
      }).toJson(),
    },
  },
  'membership_summary': members,
};

/// What an invite's stripped state gives a client: the room's type and the
/// invite itself. No roles, and no plan.
Room _invitedRoom(Client client, {required String sender}) {
  final room = Room(
    id: testSessionRoomId,
    client: client,
    membership: Membership.invite,
  );
  room.setState(
    activitySessionStateEvent(
      room,
      type: EventTypes.RoomCreate,
      content: {
        'type': '${PangeaRoomTypes.activitySession}:$testSessionActivityId',
      },
    ),
  );
  room.setState(
    Event(
      type: EventTypes.RoomMember,
      content: {'membership': 'invite'},
      stateKey: client.userID,
      senderId: sender,
      eventId: '\$invite',
      originServerTs: DateTime.utc(2026, 1, 1, 12),
      room: room,
    ),
  );
  return room;
}

/// Answers the choreographer's reads of the session's plan: one at a time
/// for the page, and in a batch for hydration.
http.Client _planServer() => MockClient((request) async {
  final plan = {
    'plan': {
      'activity_id': testSessionActivityId,
      'user_id': testSessionUserId,
      'title': 'Meet a Fan at the Stadium',
      'roles': [
        {'role_id': 'r1', 'name': 'Fan'},
        {'role_id': 'r2', 'name': 'Visitor'},
      ],
    },
    'l1': 'en',
    'version_id': 'v1',
  };
  return http.Response(
    jsonEncode(
      request.url.path.endsWith('/batch')
          ? {
              'activities': {testSessionActivityId: plan},
              'removed': [],
              'unavailable': [],
            }
          : plan,
    ),
    200,
  );
});

/// Answers the session's preview, the invite's join and leave; everything else
/// goes to [FakeMatrixApi], which knows none of them.
class _InviteServer extends http.BaseClient {
  final FakeMatrixApi _fallback = FakeMatrixApi();

  /// The room's preview. Empty answers as if the room had none.
  Map<String, dynamic> preview = const {};

  int previewStatus = 200;
  int previewReads = 0;

  /// Holds the preview's answer until it completes.
  Future<void>? previewHeldUntil;

  /// The membership requests sent, in order.
  final List<String> memberships = [];

  http.StreamedResponse _json(int status, Object body) => http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    status,
    headers: {'content-type': 'application/json'},
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/room_preview')) {
      previewReads++;
      await previewHeldUntil;
      return _json(previewStatus, {
        'rooms': {testSessionRoomId: preview},
      });
    }
    if (path.endsWith('/leave')) {
      memberships.add('leave');
      return _json(200, {});
    }
    if (path.endsWith('/join')) {
      memberships.add('join');
      return _json(200, {'room_id': testSessionRoomId});
    }
    return _fallback.send(request);
  }
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
