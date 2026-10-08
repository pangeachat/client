import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// Forwarding from the share dialog (CLIENT-EZ7).
///
/// The dialog is opened with `showDialog`, which pushes a pageless route on
/// the root navigator. `GoRouterState.of` cannot resolve from there: the
/// dialog's route is not a GoRouter page, so it climbs to the root navigator's
/// own context, which has no route above it, and throws. The throw landed in
/// the Forward button's handler after the dialog had already closed, so the
/// learner saw the dialog vanish and nothing get forwarded.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomId = '!target:fakeServer.notExisting';
  const roomName = 'Target chat';

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
  });

  setUp(() async {
    // The room tiles resolve the homeserver from the env.
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeServer.notExisting'},
    );
    client = await getTestClient();
    final room = Room(id: roomId, client: client, membership: Membership.join);
    room.setState(
      Event(
        type: EventTypes.RoomName,
        content: {'name': roomName},
        stateKey: '',
        senderId: client.userID!,
        eventId: '\$name',
        originServerTs: DateTime.utc(2026, 1, 1),
        room: room,
      ),
    );
    client.rooms.add(room);
  });

  tearDown(() async => client.dispose());

  testWidgets('Forward opens the chosen room and hands it the items', (
    tester,
  ) async {
    final items = <ShareItem>[TextShareItem('hola')];
    Object? deliveredExtra;

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            deliveredExtra = state.extra;
            return Scaffold(
              body: Builder(
                builder: (inner) => TextButton(
                  onPressed: () => showScaffoldDialog(
                    context: inner,
                    builder: (_) => ShareScaffoldDialog(items: items),
                  ),
                  child: const Text('share'),
                ),
              ),
            );
          },
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
    // L10n's delegate resolves from a deferred library, so nothing is in the
    // tree until localizations finish loading.
    await tester.pumpAndSettle();

    await tester.tap(find.text('share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(roomName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forward'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ShareScaffoldDialog), findsNothing);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      WorkspaceNav.openExclusiveLeftRoom(
        Uri.parse('/'),
        RoomPanelToken(RoomTokenParam(id: shortRoomId(roomId))),
      ),
      reason: 'Forward must open the chosen room as the live chat',
    );
    expect(
      deliveredExtra,
      same(items),
      reason: 'the shell forwards the items it receives in `extra`',
    );
  });
}

/// Skips `initMatrix()` — the dialog only needs the client back out of the
/// tree (`Matrix.of(context).client`), not a booted app.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {
    MatrixState.pangeaController = FakePangeaController();
  }
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
