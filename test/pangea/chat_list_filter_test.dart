import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'get_test_client.dart';

/// The chat list's filter pills sort chats into DMs, Groups and Activities
/// (#9007). Each category is exclusive — an activity session is a non-direct
/// group room by shape, but the Groups pill must not carry it — and "All"
/// shows every visible chat so nothing is ever lost to a filter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const friendId = '@friend:fakeServer.notExisting';

  late Client client;
  late ChatListController controller;

  late Room dm;
  late Room group;
  late Room activity;
  late Room space;
  late Room analytics;

  Room addRoom(String id, {String? directChatWith, String? createType}) {
    final room = Room(id: id, client: client, membership: Membership.join);
    if (createType != null) {
      room.setState(
        Event(
          type: EventTypes.RoomCreate,
          content: {'type': createType},
          stateKey: '',
          senderId: userId,
          eventId: '\$create$id',
          originServerTs: DateTime.now(),
          room: room,
        ),
      );
    }
    if (directChatWith != null) {
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          directChatWith: [id],
        },
      );
    }
    client.rooms.add(room);
    return room;
  }

  setUp(() async {
    client = await getTestClient();
    controller = const ChatList(activeChat: null).createState();

    dm = addRoom('!dm:fakeServer.notExisting', directChatWith: friendId);
    group = addRoom('!group:fakeServer.notExisting');
    activity = addRoom(
      '!activity:fakeServer.notExisting',
      createType: '${PangeaRoomTypes.activitySession}:test-activity',
    );
    space = addRoom('!space:fakeServer.notExisting', createType: 'm.space');
    analytics = addRoom(
      '!analytics:fakeServer.notExisting',
      createType: PangeaRoomTypes.analytics,
    );
  });

  tearDown(() async {
    await client.dispose();
  });

  List<Room> roomsFor(ActiveFilter filter) => client.rooms
      .where(controller.getRoomFilterByActiveFilter(filter))
      .toList();

  test('All shows every chat but never spaces or hidden rooms', () {
    expect(roomsFor(ActiveFilter.allChats), [dm, group, activity]);
    expect(roomsFor(ActiveFilter.allChats), isNot(contains(space)));
    expect(roomsFor(ActiveFilter.allChats), isNot(contains(analytics)));
  });

  test('DMs shows only direct chats', () {
    expect(roomsFor(ActiveFilter.messages), [dm]);
  });

  test('Groups shows non-direct chats but not activity sessions', () {
    expect(roomsFor(ActiveFilter.groups), [group]);
  });

  test('Activities shows only activity sessions', () {
    expect(roomsFor(ActiveFilter.activities), [activity]);
  });

  test('every visible chat lands in exactly one category pill', () {
    final categorized = [
      ...roomsFor(ActiveFilter.messages),
      ...roomsFor(ActiveFilter.groups),
      ...roomsFor(ActiveFilter.activities),
    ];
    expect(categorized, unorderedEquals(roomsFor(ActiveFilter.allChats)));
  });
}
