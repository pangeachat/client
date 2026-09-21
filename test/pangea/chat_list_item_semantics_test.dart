import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// #8745 — the naming half of #8689 finding 12: every chat-list row composes
/// its accessible name from the same non-empty parts (name, unread, timestamp,
/// preview), joined once, so no row announces a dangling separator and the
/// visible timestamp is spoken on every row that shows one.
void main() {
  late Client client;

  const roomId = '!chat:fakeServer.notExisting';
  const roomName = 'Library registration roleplay';
  const senderId = '@alice:example.org';

  setUpAll(() {
    // `Avatar` resolves the bot name from the environment at build time.
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
    // The message-preview path reads `languagesSet` off the static controller.
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room makeRoom({
    Membership membership = Membership.join,
    String? roomType,
    bool withMessage = true,
  }) {
    final room = Room(id: roomId, client: client, membership: membership);
    room.setState(
      Event(
        type: EventTypes.RoomName,
        content: {'name': roomName},
        stateKey: '',
        senderId: senderId,
        eventId: '\$name',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    if (roomType != null) {
      room.setState(
        Event(
          type: EventTypes.RoomCreate,
          content: {'type': roomType},
          stateKey: '',
          senderId: senderId,
          eventId: '\$create',
          originServerTs: DateTime.now(),
          room: room,
        ),
      );
    }
    room.setState(
      Event(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'displayname': 'Alice'},
        stateKey: senderId,
        senderId: senderId,
        eventId: '\$member',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    if (withMessage) {
      room.lastEvent = Event(
        type: EventTypes.Message,
        content: {'msgtype': 'm.text', 'body': 'hola amiga'},
        senderId: senderId,
        eventId: '\$msg',
        originServerTs: DateTime.now(),
        room: room,
      );
    }
    return room;
  }

  Future<BuildContext> pumpItem(WidgetTester tester, Room room) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: 380, child: ChatListItem(room, onTap: () {})),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so the row isn't in
    // the tree until localizations finish loading.
    await tester.pumpAndSettle();
    return tester.element(find.byType(ChatListItem));
  }

  /// No node anywhere in the row may end in a hand-placed separator — the
  /// dangling "Room name, " the triage measured on rows whose subtitle
  /// carries no text.
  void expectNoDanglingSeparator() {
    expect(
      find.bySemanticsLabel(RegExp(r',\s*$')),
      findsNothing,
      reason: 'no accessible name may end in a dangling separator',
    );
  }

  String expectedPreview(BuildContext context, Room room) =>
      room.lastEvent!.calcLocalizedBodyFallback(
        MatrixLocals(L10n.of(context)),
        hideReply: true,
        hideEdit: true,
        plaintextBody: true,
        removeMarkdown: true,
        withSenderNamePrefix: true,
      );

  testWidgets('a plain room announces name, timestamp, and preview', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final room = makeRoom();
    final context = await pumpItem(tester, room);

    final time = room.latestEventReceivedTime.localizedTimeShort(context);
    expect(
      find.bySemanticsLabel(
        '$roomName, $time, ${expectedPreview(context, room)}',
      ),
      findsOneWidget,
    );
    expectNoDanglingSeparator();
    semantics.dispose();
  });

  testWidgets('a marked-unread room announces Unread between name and '
      'timestamp', (tester) async {
    final semantics = tester.ensureSemantics();
    final room = makeRoom();
    room.roomAccountData['m.marked_unread'] = BasicEvent(
      type: 'm.marked_unread',
      content: {'unread': true},
    );
    final context = await pumpItem(tester, room);

    final l10n = L10n.of(context);
    final time = room.latestEventReceivedTime.localizedTimeShort(context);
    expect(
      find.bySemanticsLabel(
        '$roomName, ${l10n.unread}, $time, ${expectedPreview(context, room)}',
      ),
      findsOneWidget,
    );
    expectNoDanglingSeparator();
    semantics.dispose();
  });

  testWidgets('a room with notifications leaves the count announcement to '
      'the bubble — no double Unread', (tester) async {
    final semantics = tester.ensureSemantics();
    final room = makeRoom();
    room.notificationCount = 1;
    final context = await pumpItem(tester, room);

    final l10n = L10n.of(context);
    final time = room.latestEventReceivedTime.localizedTimeShort(context);
    // The row node merges its parts with a newline: the composed name first,
    // then the bubble's own "Unread: 1".
    expect(
      find.bySemanticsLabel(
        '$roomName, $time, ${expectedPreview(context, room)}\n'
        '${l10n.unreadLabel('1')}',
      ),
      findsOneWidget,
    );
    expectNoDanglingSeparator();
    semantics.dispose();
  });

  testWidgets(
    'a not-yet-started activity row (no visible subtitle text) still ends '
    'cleanly — the dangling-comma reproduction',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final room = makeRoom(
        roomType: '${PangeaRoomTypes.activitySession}:library-reg',
      );
      final context = await pumpItem(tester, room);

      final time = room.latestEventReceivedTime.localizedTimeShort(context);
      expect(
        find.bySemanticsLabel('$roomName, $time'),
        findsOneWidget,
        reason:
            'role avatars are the whole visible subtitle, so the name is '
            'just name + timestamp — with no trailing separator',
      );
      expectNoDanglingSeparator();
      semantics.dispose();
    },
  );

  testWidgets('an invited room announces the Invited state, no timestamp', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final room = makeRoom(membership: Membership.invite, withMessage: false);
    final context = await pumpItem(tester, room);

    final l10n = L10n.of(context);
    expect(find.bySemanticsLabel('$roomName, ${l10n.invited}'), findsOneWidget);
    expectNoDanglingSeparator();
    semantics.dispose();
  });
}
