import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_constants.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_room_subpage.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// #9297 — a new activity session opens as soon as /createRoom returns, before
/// the room reaches the local store. The room panel waits, bounded, for the
/// room to sync instead of showing "no longer participating" at once.
void main() {
  late Client client;

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
    MatrixState.pangeaController = FakePangeaController();
    client = await getTestClient();
  });

  tearDownAll(() async {
    await client.dispose();
  });

  Future<void> pumpPanel(WidgetTester tester, String roomId) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Provider<MatrixState>.value(
          value: _FakeMatrixState(client),
          child: LeftPanelRoomSubpage(
            tokenType: PanelTypesEnum.session,
            param: RoomTokenParam(id: roomId),
            shareItems: null,
            closeButton: const CloseButton(),
          ),
        ),
      ),
    );
    // Localizations load asynchronously; nothing renders until they have.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// The panel under a router, as in the app: a space token is replaced
  /// with the course or a ping's activity, which needs the router.
  Future<GoRouter> pumpRoutedPanel(
    WidgetTester tester,
    String roomId, {
    String? eventId,
  }) async {
    final router = GoRouter(
      initialLocation: WorkspaceNav.openRoomById(
        Uri.parse('/'),
        roomId,
        event: eventId,
      ),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Provider<MatrixState>.value(
            value: _FakeMatrixState(client),
            child: LeftPanelRoomSubpage(
              tokenType: PanelTypesEnum.room,
              param: RoomTokenParam(id: roomId, eventId: eventId),
              shareItems: null,
              closeButton: const CloseButton(),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return router;
  }

  SyncUpdate spaceSync(
    String roomId, {
    List<MatrixEvent> timeline = const [],
  }) => SyncUpdate(
    nextBatch: 'space-$roomId',
    rooms: RoomsUpdate(
      join: {
        roomId: JoinedRoomUpdate(
          state: [
            MatrixEvent(
              type: EventTypes.RoomCreate,
              content: {'type': 'm.space'},
              stateKey: '',
              senderId: client.userID!,
              eventId: '\$create-$roomId',
              originServerTs: DateTime.now(),
            ),
          ],
          timeline: TimelineUpdate(events: timeline),
        ),
      },
    ),
  );

  String unavailableText(WidgetTester tester) => L10n.of(
    tester.element(find.byType(LeftPanelRoomSubpage)),
  ).youAreNoLongerParticipatingInThisChat;

  testWidgets('an id that never syncs shows a spinner, then the unavailable '
      'state after the bound', (tester) async {
    await pumpPanel(tester, '!never-syncs:example.org');

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(CloseButton), findsOneWidget);
    expect(find.text(unavailableText(tester)), findsNothing);

    await tester.pump(const Duration(seconds: 9));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(unavailableText(tester)), findsOneWidget);
  });

  testWidgets('the wait ends when the room syncs, not on the bound', (
    tester,
  ) async {
    const roomId = '!arrives:example.org';
    final router = await pumpRoutedPanel(tester, roomId);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // A space arrives. A space has no chat, so the panel replaces its token
    // with the course: the replacement happening at all is what pins that the
    // wait ended on the sync rather than on the bound.
    await tester.runAsync(() => client.handleSync(spaceSync(roomId)));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(client.getRoomById(roomId), isNotNull);
    expect(find.text(unavailableText(tester)), findsNothing);
    final uri = router.routerDelegate.currentConfiguration.uri;
    expect(activeSpaceIdFor(uri), roomId);
    expect(parseOpenPanels(uri).left.map((t) => t.type), [
      PanelTypesEnum.course,
    ]);
  });

  testWidgets('a course ping link opens the ping\'s activity (#9401)', (
    tester,
  ) async {
    const roomId = '!pingspace:example.org';
    const pingId = r'$ping:example.org';
    await tester.runAsync(
      () => client.handleSync(
        spaceSync(
          roomId,
          timeline: [
            MatrixEvent(
              type: EventTypes.Message,
              content: {
                'msgtype': MessageTypes.Text,
                'body': 'Join us!',
                CoursePingConstants.coursePingRoomId: '!session:example.org',
                CoursePingConstants.coursePingActivityId: 'activity-9401',
              },
              senderId: '@teacher:example.org',
              eventId: pingId,
              originServerTs: DateTime.now(),
            ),
          ],
        ),
      ),
    );

    final router = await pumpRoutedPanel(tester, roomId, eventId: pingId);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();
    }

    final uri = router.routerDelegate.currentConfiguration.uri;
    expect(activeSpaceIdFor(uri), roomId);
    final left = parseOpenPanels(uri).left;
    expect(left, hasLength(1));
    final param = (left.single as ActivityPanelToken).param!;
    expect(param.activityId, 'activity-9401');
    expect(param.roomId, '!session:example.org');
  });
}
