import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_context_menu_action.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'get_test_client.dart';

/// #9107 — every action a chat-list row's long-press menu offers has to be
/// reachable from the chat's own header menu too, for the learners who never
/// discover the long press. The only action the header drops is `open`: the
/// chat it would open is already on screen.
void main() {
  late Client client;

  const roomId = '!chat:fakeServer.notExisting';
  const spaceId = '!course:fakeServer.notExisting';
  const userId = '@test:fakeServer.notExisting';

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

  void setStateEvent(
    Room room,
    String type,
    Map<String, Object?> content, {
    String stateKey = '',
  }) => room.setState(
    Event(
      type: type,
      content: content,
      stateKey: stateKey,
      senderId: userId,
      eventId: '\$${type}_${room.id}_$stateKey',
      originServerTs: DateTime.now(),
      room: room,
    ),
  );

  /// A joined group chat inside a course space, with the account at admin
  /// power — the room that turns on the widest set of actions, so parity is
  /// tested over all of them rather than the handful a plain DM offers.
  Room buildRoom() {
    final space = Room(
      id: spaceId,
      client: client,
      membership: Membership.join,
    );
    setStateEvent(space, EventTypes.RoomCreate, {'type': 'm.space'});
    setStateEvent(space, EventTypes.RoomName, {'name': 'Spanish 101'});
    setStateEvent(space, EventTypes.SpaceChild, {
      'via': ['fakeServer.notExisting'],
    }, stateKey: roomId);

    final room = Room(id: roomId, client: client, membership: Membership.join);
    setStateEvent(room, EventTypes.RoomCreate, {});
    setStateEvent(room, EventTypes.RoomName, {'name': 'Study group'});
    setStateEvent(room, EventTypes.RoomPowerLevels, {
      'users': {userId: 100},
    });

    client.rooms.addAll([space, room]);
    return room;
  }

  Future<BuildContext> pumpContext(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    // L10n's delegate resolves from a deferred library, so nothing under the
    // MaterialApp is in the tree until localizations finish loading.
    await tester.pumpAndSettle();
    return tester.element(find.byType(Scaffold));
  }

  Set<ChatContextAction> actionsFor(
    BuildContext context,
    Room room,
    ChatMenuSource source,
  ) => chatContextMenuItems(
    context,
    room: room,
    space: room.pangeaSpaceParents.firstOrNull,
    source: source,
  ).whereType<PopupMenuItem<ChatContextAction>>().map((i) => i.value!).toSet();

  testWidgets('the chat header offers every chat-list action but open', (
    tester,
  ) async {
    final room = buildRoom();
    final context = await pumpContext(tester);

    final list = actionsFor(context, room, ChatMenuSource.chatList);
    final header = actionsFor(context, room, ChatMenuSource.chatHeader);

    // The room is set up to turn these on; if it stops doing so the parity
    // assertion below would pass over an empty menu and prove nothing.
    expect(
      list,
      containsAll([
        ChatContextAction.open,
        ChatContextAction.goToSpace,
        ChatContextAction.mute,
        ChatContextAction.markUnread,
        ChatContextAction.favorite,
        ChatContextAction.leave,
        ChatContextAction.delete,
      ]),
    );

    expect(header, containsAll(list.difference({ChatContextAction.open})));
    expect(header, isNot(contains(ChatContextAction.open)));
    expect(
      header,
      containsAll([ChatContextAction.search, ChatContextAction.details]),
    );
    expect(list, isNot(contains(ChatContextAction.search)));
    expect(list, isNot(contains(ChatContextAction.details)));
  });
}
