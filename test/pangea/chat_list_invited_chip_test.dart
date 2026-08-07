import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/invited_chip.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'get_test_client.dart';

/// #8191 — an activity invite is easy to miss in the chat list when it reads in
/// the same grey as every other row ("📨 Invite chat"). It now wears the gold
/// `InvitedChip` an invited course tile wears, so an unanswered invitation looks
/// the same wherever the learner meets it.
///
/// The nav badge that turns gold alongside it ([UnreadRoomsBadge]) needs a
/// mounted `MatrixState`, so its half of the change is covered through the
/// shared predicate both surfaces read — [KnockRoomExtension.isPendingInvite].
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const roomId = '!chat:fakeServer.notExisting';

  setUpAll(() {
    // `Avatar` resolves the bot name from the environment at build time.
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
  });

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  /// Marks [roomId] as a room this learner knocked on, which is how an accepted
  /// knock comes back wearing `Membership.invite`.
  void recordKnock(String id) {
    client.accountData[PangeaEventTypes.knockedRooms] = BasicEvent(
      type: PangeaEventTypes.knockedRooms,
      content: KnockedRoomsModel(knockedRoomIds: [id]).toJson(),
    );
  }

  Room room({required Membership membership, String id = roomId}) {
    final room = Room(id: id, client: client, membership: membership);
    room.setState(
      Event(
        type: EventTypes.RoomName,
        content: {'name': 'Farewell Lunch Face-off'},
        stateKey: '',
        senderId: userId,
        eventId: '\$name',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    return room;
  }

  Future<void> pumpItem(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: 380, child: ChatListItem(room, onTap: () {})),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so the row isn't in the
    // tree until localizations finish loading.
    await tester.pumpAndSettle();
  }

  group('isPendingInvite', () {
    test('an unanswered invite is one', () {
      expect(room(membership: Membership.invite).isPendingInvite, isTrue);
    });

    test('a joined room is not', () {
      expect(room(membership: Membership.join).isPendingInvite, isFalse);
    });

    test('an approved knock is not, though it arrives as an invite', () {
      recordKnock(roomId);
      final knocked = room(membership: Membership.invite);

      expect(knocked.membership, Membership.invite);
      expect(
        knocked.isPendingInvite,
        isFalse,
        reason:
            'acceptKnock grants a knock by inviting the knocker — the learner '
            'asked to be here, so nothing may claim they were invited',
      );
    });
  });

  testWidgets('an invited chat wears the gold Invited chip', (tester) async {
    await pumpItem(tester, room(membership: Membership.invite));

    final context = tester.element(find.byType(ChatListItem));

    expect(find.byType(InvitedChip), findsOneWidget);
    expect(find.text(L10n.of(context).invited), findsOneWidget);
    expect(
      find.text(L10n.of(context).inviteChat),
      findsNothing,
      reason: 'the grey line the chip replaces',
    );
  });

  testWidgets('a joined chat wears no chip', (tester) async {
    await pumpItem(tester, room(membership: Membership.join));
    expect(find.byType(InvitedChip), findsNothing);
  });

  testWidgets('an approved knock is not dressed up as an invitation', (
    tester,
  ) async {
    recordKnock(roomId);
    await pumpItem(tester, room(membership: Membership.invite));

    expect(find.byType(InvitedChip), findsNothing);
  });
}
