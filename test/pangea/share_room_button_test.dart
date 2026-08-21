import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/custom_join_rules_model.dart';
import 'package:fluffychat/features/join_codes/share_room_button.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'get_test_client.dart';

/// Activity sessions have no code-entry surface to join with, so the share
/// menu must offer only "Share link" there — the invite-code option stays
/// for other rooms (e.g. course spaces), which do have a code-join flow
/// (#8529).
void main() {
  late Client client;
  late L10n l10n;

  const userId = '@test:fakeServer.notExisting';
  const roomId = '!1234:fakeServer.notExisting';
  const joinCode = 'abc1234';

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  Room buildRoom({required bool isActivitySession}) {
    final room = Room(id: roomId, client: client);
    if (isActivitySession) {
      room.setState(
        Event(
          type: EventTypes.RoomCreate,
          content: {'type': '${PangeaRoomTypes.activitySession}:test-activity'},
          senderId: userId,
          eventId: '\$create',
          originServerTs: DateTime.utc(2026, 1, 1, 12),
          stateKey: '',
          room: room,
        ),
      );
    }
    room.setState(
      Event(
        type: EventTypes.RoomJoinRules,
        content: CustomJoinRulesModel(
          joinRule: JoinRules.public,
          accessCode: joinCode,
        ).toJson(),
        senderId: userId,
        eventId: '\$joinRules',
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        stateKey: '',
        room: room,
      ),
    );
    return room;
  }

  Future<void> pumpButton(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = L10n.of(context);
            return Scaffold(
              body: ShareRoomButton(
                room: room,
                child: const Icon(Icons.share_outlined),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ShareRoomButton));
    await tester.pumpAndSettle();
  }

  testWidgets('non-activity room share menu offers link and invite code', (
    tester,
  ) async {
    final room = buildRoom(isActivitySession: false);
    await pumpButton(tester, room);
    expect(find.text(l10n.shareSpaceLink), findsOneWidget);
    expect(find.text(l10n.shareInviteCode(joinCode)), findsOneWidget);
  });

  testWidgets('activity session share menu hides invite code', (tester) async {
    final room = buildRoom(isActivitySession: true);
    await pumpButton(tester, room);
    expect(find.text(l10n.shareSpaceLink), findsOneWidget);
    expect(find.text(l10n.shareInviteCode(joinCode)), findsNothing);
  });
}
