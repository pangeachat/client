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
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'activity_session_fixtures.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #9417 — leaving or deleting a session from its waiting room's "…" menu
/// closes the session's panel.
///
/// The menu exists only while the page is a waiting room, and the page stops
/// being one as soon as the leave (or the delete's kick) lands in sync. So the
/// menu button is gone before the sync has finished, and a close that
/// navigated from the button's own context never ran: the panel stayed open on
/// role selection for a room the learner had already left.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // GetStorage writes through path_provider, which has no implementation on
  // the test host.
  final tempDir = Directory.systemTemp.createTempSync('waiting_room_exit');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  late _ExitServer server;
  late Client client;
  late SharedPreferences store;

  /// Runs a second of frames. This page never settles: the waiting room's
  /// clock ticks every second, and the plan, which has no server here, stays
  /// loading. So `pumpAndSettle` would time out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUpAll(() async {
    dotenv.testLoad(
      mergeWith: {
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
        'BOT_NAME': '@bot:fakeServer.notExisting',
      },
    );
    await GetStorage.init('env_override');
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
  });

  setUp(() async {
    server = _ExitServer();
    client = await getTestClient(httpClient: server);
    MatrixState.pangeaController = FakePangeaController(client: client);

    // The waiting room: the learner holds one of the two seats, so the
    // session has not started. Admin power, so the menu offers Delete too.
    final room = activitySessionRoom(
      client,
      roles: {
        'r1': ActivityRoleModel(
          id: 'r1',
          userId: testSessionUserId,
          role: 'Fan',
        ),
      },
    );
    room.setState(
      activitySessionStateEvent(
        room,
        type: EventTypes.RoomPowerLevels,
        content: {
          'users': {testSessionUserId: 100},
        },
      ),
    );
    // The chat panel loads the room's timeline before it shows the start
    // page, and that loads all of the room's state (`Room.postLoad`). Only a
    // loaded room applies the leave's member event, which is what tells the
    // page the learner is gone.
    room.partial = false;
    client.rooms.add(room);
  });

  tearDown(() async => client.dispose());

  /// The session open as a room panel beside the chat list, which is where
  /// confirming a role leaves the learner.
  Future<GoRouter> pumpWaitingRoom(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/?left=chats,room:${shortRoomId(testSessionRoomId)}',
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
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
          // The test font draws every glyph a full em wide, which pushes the
          // menu's longer rows past the menu's fixed width; real text fits.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.5)),
            child: child!,
          ),
        ),
      ),
    );
    await settle(tester);
    return router;
  }

  /// The learner's own membership turning to leave: what a leave, or the
  /// kick a delete sends first, looks like in sync.
  Future<void> syncLeave(WidgetTester tester, {required String sender}) =>
      tester.runAsync(
        () => client.handleSync(
          SyncUpdate(
            nextBatch: 'after_exit',
            rooms: RoomsUpdate(
              leave: {
                testSessionRoomId: LeftRoomUpdate(
                  timeline: TimelineUpdate(
                    events: [
                      MatrixEvent(
                        type: EventTypes.RoomMember,
                        content: {'membership': 'leave'},
                        senderId: sender,
                        stateKey: testSessionUserId,
                        eventId: '\$exit',
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

  List<PanelTypesEnum> leftPanels(GoRouter router) => parseOpenPanels(
    router.routeInformationProvider.value.uri,
  ).left.map((t) => t.type).toList();

  /// Opens the "…" menu, picks [action], and confirms it.
  Future<void> chooseAndConfirm(WidgetTester tester, String action) async {
    await tester.tap(find.byTooltip(_l10n(tester).moreOptions));
    await settle(tester);
    await tester.tap(find.text(action));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, action));
    await tester.pump();
  }

  testWidgets('Leave closes the panel once the leave lands in sync', (
    tester,
  ) async {
    final router = await pumpWaitingRoom(tester);
    expect(leftPanels(router), [PanelTypesEnum.chats, PanelTypesEnum.room]);

    await chooseAndConfirm(tester, _l10n(tester).leave);
    // The server answers the leave at once, but the client reads that answer
    // on the real clock (it was built outside the test's fake one). Wait for
    // it, which closes the loading dialog, so the sync arrives after it.
    final loading = find.byWidgetPredicate((w) => w is LoadingDialog);
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 100 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(loading, findsNothing);
    expect(server.exits, ['leave']);
    // The panel waits for the leave to land in sync.
    expect(leftPanels(router), [PanelTypesEnum.chats, PanelTypesEnum.room]);

    await syncLeave(tester, sender: testSessionUserId);
    // The page re-reads the room before the sync has finished processing,
    // and a room the learner left is no waiting room.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byTooltip(_l10n(tester).moreOptions), findsNothing);

    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
    await settle(tester);

    expect(leftPanels(router), [PanelTypesEnum.chats]);
    // Lets the page's one-second limit on room-state rebuilds run out.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Delete closes the panel when the kick syncs before the delete '
      'returns', (tester) async {
    final router = await pumpWaitingRoom(tester);
    // Made here, not in setUp: completing a future from outside the test's
    // fake clock would never wake the request waiting on it.
    final deleteReturns = Completer<void>();
    server.deleteHeldUntil = deleteReturns.future;

    await chooseAndConfirm(tester, _l10n(tester).delete);
    // Past the loading dialog's short delay, so it is up.
    await tester.pump(const Duration(milliseconds: 400));
    expect(server.exits, ['delete']);

    // Deleting a room kicks everyone before the request returns.
    await syncLeave(tester, sender: '@admin:fakeServer.notExisting');
    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byTooltip(_l10n(tester).moreOptions), findsNothing);
    expect(leftPanels(router), [PanelTypesEnum.chats, PanelTypesEnum.room]);

    deleteReturns.complete();
    await settle(tester);

    expect(leftPanels(router), [PanelTypesEnum.chats]);
    // Lets the page's one-second limit on room-state rebuilds run out.
    await tester.pump(const Duration(seconds: 1));
  });
}

L10n _l10n(WidgetTester tester) =>
    L10n.of(tester.element(find.byType(ActivitySessionStartPage)));

/// Answers the waiting room's leave and delete itself; everything else goes
/// to [FakeMatrixApi], which knows neither this room nor the delete endpoint.
class _ExitServer extends http.BaseClient {
  final FakeMatrixApi _fallback = FakeMatrixApi();

  /// The exit requests sent, in order.
  final List<String> exits = [];

  /// Holds the delete's answer until it completes, so the kick can land in
  /// sync first.
  Future<void>? deleteHeldUntil;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/leave')) {
      exits.add('leave');
    } else if (path.endsWith('/pangea/v1/delete_room')) {
      exits.add('delete');
      await deleteHeldUntil;
    } else {
      return _fallback.send(request);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({}))),
      200,
      headers: {'content-type': 'application/json'},
    );
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
