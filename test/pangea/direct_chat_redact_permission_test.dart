import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'get_test_client.dart';

/// Direct chats are created with the SDK's `trusted_private_chat` preset, which
/// puts BOTH members at PL 100. Power levels alone would therefore let each
/// member redact the other's messages — which no other room type allows a
/// non-moderator to do. [Room.canRedactEventFrom] closes that gap: in a direct
/// chat you may only redact your own messages (#8402).
///
/// Group rooms keep the power-level rule so instructors can still moderate.
void main() {
  const ownUserId = '@test:fakeServer.notExisting';
  const otherUserId = '@other:fakeServer.notExisting';

  late Client client;

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room room({
    required int ownPowerLevel,
    required bool isDirectChat,
    Membership membership = Membership.join,
  }) {
    final room = Room(
      id: '!room:fakeServer.notExisting',
      client: client,
      membership: membership,
    );
    room.setState(
      Event(
        type: EventTypes.RoomPowerLevels,
        content: {
          ...RoomDefaults.defaultPowerLevelsContent(),
          'users': {ownUserId: ownPowerLevel, otherUserId: 100},
        },
        stateKey: '',
        senderId: ownUserId,
        eventId: '\$powerLevels',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    if (isDirectChat) {
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          otherUserId: [room.id],
        },
      );
    }
    return room;
  }

  test('a direct chat member cannot redact the other member’s messages', () {
    final dm = room(ownPowerLevel: 100, isDirectChat: true);
    expect(dm.isDirectChat, true);
    expect(dm.canRedact, true, reason: 'both DM members are admins');
    expect(dm.canRedactEventFrom(otherUserId), false);
  });

  test('a direct chat member can still redact their own messages', () {
    expect(
      room(
        ownPowerLevel: 100,
        isDirectChat: true,
      ).canRedactEventFrom(ownUserId),
      true,
    );
  });

  test('a moderator can still redact others’ messages in a group room', () {
    expect(
      room(
        ownPowerLevel: 50,
        isDirectChat: false,
      ).canRedactEventFrom(otherUserId),
      true,
    );
  });

  test('a learner cannot redact others’ messages in a group room', () {
    final groupRoom = room(ownPowerLevel: 0, isDirectChat: false);
    expect(groupRoom.canRedactEventFrom(otherUserId), false);
    expect(groupRoom.canRedactEventFrom(ownUserId), true);
  });
}
