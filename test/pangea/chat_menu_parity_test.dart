import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_context_menu_action.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'activity_session_fixtures.dart';
import 'get_test_client.dart';

/// #9107 — every action a chat-list row's long-press menu offers has to be
/// reachable from the chat's own header menu too, for the learners who never
/// discover the long press. The only action the header drops is `open`: the
/// chat it would open is already on screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // GetStorage writes through path_provider, which has no implementation on
  // the test host.
  final tempDir = Directory.systemTemp.createTempSync('chat_menu_parity_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  late Client client;

  const roomId = '!chat:fakeServer.notExisting';
  const spaceId = '!course:fakeServer.notExisting';
  const userId = testSessionUserId;

  setUpAll(() async {
    // `Avatar` resolves the bot name from the environment at build time, and
    // `isActivityFinished` filters the bot out of the seat list. Both read
    // `Environment.botName`, which builds its GetStorage container on first
    // touch — inside a testWidgets FakeAsync zone that container's timer never
    // fires and the test fails on a pending timer. Build it here instead.
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
    await GetStorage.init('env_override');
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

  /// An activity session in the same course space, admin-powered like
  /// [buildRoom]. [finished] marks the one seat done, which is what makes the
  /// session finished for everyone.
  Room buildSession({
    String roomId = testSessionRoomId,
    bool finished = false,
  }) {
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

    final room = activitySessionRoom(
      client,
      roomId: roomId,
      roles: {
        'r1': ActivityRoleModel(
          id: 'r1',
          userId: userId,
          role: 'Fan',
          finishedAt: finished ? DateTime.utc(2026, 1, 1, 12) : null,
        ),
        // Both seats of twoRoleActivityPlan are taken, so the session counts as
        // started either way. That holds the leave rule constant: leave is off
        // for a learner holding a role in a started session, finished or not,
        // so completion's own effect on the menu is isolated.
        'r2': ActivityRoleModel(
          id: 'r2',
          userId: '@other:fakeServer.notExisting',
          role: 'Visitor',
          finishedAt: finished ? DateTime.utc(2026, 1, 1, 12) : null,
        ),
      },
    );
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

  testWidgets('an activity session header offers every chat-list action too', (
    tester,
  ) async {
    final room = buildSession();
    final context = await pumpContext(tester);

    final list = actionsFor(context, room, ChatMenuSource.chatList);
    final header = actionsFor(context, room, ChatMenuSource.chatHeader);

    // This is the report behind #9107's follow-up: the session's menu used to
    // be Invite / Download / Leave and carried none of these.
    expect(
      list,
      containsAll([
        ChatContextAction.goToSpace,
        ChatContextAction.mute,
        ChatContextAction.delete,
      ]),
    );

    expect(header, containsAll(list.difference({ChatContextAction.open})));
    expect(header, contains(ChatContextAction.invite));
  });

  testWidgets('completion itself removes only Invite', (tester) async {
    final live = buildSession();
    final finished = buildSession(
      roomId: '!finished:fakeServer.notExisting',
      finished: true,
    );
    final context = await pumpContext(tester);

    final liveHeader = actionsFor(context, live, ChatMenuSource.chatHeader);
    final finishedHeader = actionsFor(
      context,
      finished,
      ChatMenuSource.chatHeader,
    );

    expect(
      liveHeader.difference(finishedHeader),
      {ChatContextAction.invite, ChatContextAction.endActivity},
      reason:
          'the completion gate itself removes only Invite, because a '
          'session that has ended cannot be joined; End activity goes for a '
          'separate reason, that the learner has finished their own role',
    );
    // What a learner comes back to a finished session for has to still be
    // there.
    expect(
      finishedHeader,
      containsAll([
        ChatContextAction.goToSpace,
        ChatContextAction.mute,
        ChatContextAction.delete,
      ]),
    );
  });

  testWidgets('a session offers neither pin nor mark-unread', (tester) async {
    final room = buildSession();
    final context = await pumpContext(tester);

    final header = actionsFor(context, room, ChatMenuSource.chatHeader);
    expect(header, isNot(contains(ChatContextAction.favorite)));
    expect(header, isNot(contains(ChatContextAction.markUnread)));
  });
}
