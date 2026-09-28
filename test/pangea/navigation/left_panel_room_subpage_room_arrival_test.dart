import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
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
    await pumpPanel(tester, roomId);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // A space, so the arrived room renders the lightweight empty state rather
    // than a full ChatPage; what this pins is WHEN the spinner leaves.
    await tester.runAsync(() async {
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'arrival',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.RoomCreate,
                    content: {'type': 'm.space'},
                    stateKey: '',
                    senderId: client.userID!,
                    eventId: '\$create',
                    originServerTs: DateTime.now(),
                  ),
                ],
              ),
            },
          ),
        ),
      );
    });
    await tester.pump();
    await tester.pump();

    expect(client.getRoomById(roomId), isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(unavailableText(tester)), findsOneWidget);
  });
}
