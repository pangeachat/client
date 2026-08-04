import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_room_subpage.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';

/// Once the user leaves a room, `getRoomById` still returns the archived copy,
/// so a live `room:` panel must not render it as a chat — before #8148 it did,
/// and the chat's participant loader spun forever. The panel now drops to the
/// same "no longer participating" empty state used for an unknown room.
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

void main() {
  late Client client;

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  Future<void> pumpRoomPanel(
    WidgetTester tester, {
    required String roomId,
    String? subpage,
  }) async {
    const closeKey = Key('the-close-button');
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrixState(client),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: LeftPanelRoomSubpage(
              tokenType: PanelTypesEnum.room,
              param: RoomTokenParam(id: roomId, subpage: subpage),
              shareItems: null,
              closeButton: const IconButton(
                key: closeKey,
                icon: Icon(Icons.close),
                onPressed: null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a room: panel for a left room shows the no-longer-participating state '
    '(#8148)',
    (tester) async {
      const roomId = '!left:fakeServer.notExisting';
      client.rooms.add(
        Room(id: roomId, membership: Membership.leave, client: client),
      );

      await pumpRoomPanel(tester, roomId: roomId);

      final l10n = L10n.of(tester.element(find.byType(LeftPanelRoomSubpage)));
      expect(
        find.text(l10n.youAreNoLongerParticipatingInThisChat),
        findsOneWidget,
      );
      expect(find.byKey(const Key('the-close-button')), findsOneWidget);
    },
  );

  testWidgets(
    'the gate also covers sub-pages, so backing out of chat details on a left '
    'room cannot strand the user (#8148 repro path)',
    (tester) async {
      const roomId = '!left:fakeServer.notExisting';
      client.rooms.add(
        Room(id: roomId, membership: Membership.leave, client: client),
      );

      await pumpRoomPanel(tester, roomId: roomId, subpage: 'details');

      final l10n = L10n.of(tester.element(find.byType(LeftPanelRoomSubpage)));
      expect(
        find.text(l10n.youAreNoLongerParticipatingInThisChat),
        findsOneWidget,
      );
    },
  );
}
