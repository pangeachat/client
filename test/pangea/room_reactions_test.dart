import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/reaction_listener.dart';
import 'get_test_client.dart';

/// A read-only room (announcements) has no `m.reaction` power level of its own,
/// so a learner's reaction is rejected by the server. The UI offers reactions
/// only where [Room.canSendReactions], and a send that fails anyway must not
/// leave its local echo behind looking like a delivered reaction (#9167).
void main() {
  const ownUserId = '@test:fakeServer.notExisting';

  /// The one room id [FakeMatrixApi] accepts sends to; any other is rejected.
  const writableRoomId = '!1234:fakeServer.notExisting';
  const rejectingRoomId = '!readonly:fakeServer.notExisting';
  const messageId = '\$message';

  late Client client;

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room room({
    required Map<String, dynamic> powerLevels,
    int ownPowerLevel = 0,
    String id = writableRoomId,
    Membership membership = Membership.join,
  }) {
    final room = Room(id: id, client: client, membership: membership);
    room.setState(
      Event(
        type: EventTypes.RoomPowerLevels,
        content: {
          ...powerLevels,
          'users': {ownUserId: ownPowerLevel},
        },
        stateKey: '',
        senderId: ownUserId,
        eventId: '\$powerLevels',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    client.rooms.add(room);
    return room;
  }

  group('canSendReactions', () {
    test('a learner cannot react in a read-only room', () {
      expect(
        room(
          powerLevels: RoomDefaults.restrictedPowerLevelsContent,
        ).canSendReactions,
        false,
      );
    });

    test('a moderator can react in a read-only room', () {
      expect(
        room(
          powerLevels: RoomDefaults.restrictedPowerLevelsContent,
          ownPowerLevel: 50,
        ).canSendReactions,
        true,
      );
    });

    test('a learner can react in an ordinary chat', () {
      expect(
        room(
          powerLevels: RoomDefaults.defaultPowerLevelsContent(),
        ).canSendReactions,
        true,
      );
    });

    test('nobody can react in a room they have not joined', () {
      expect(
        room(
          powerLevels: RoomDefaults.defaultPowerLevelsContent(),
          membership: Membership.invite,
        ).canSendReactions,
        false,
      );
    });
  });

  group('sendReactionOrDiscard', () {
    Set<Event> reactions(Timeline timeline) =>
        timeline.aggregatedEvents[messageId]?[RelationshipTypes.reaction] ?? {};

    test('keeps a reaction the server accepted', () async {
      final accepting = room(
        powerLevels: RoomDefaults.defaultPowerLevelsContent(),
      );
      final timeline = await accepting.getTimeline();

      await accepting.sendReactionOrDiscard(messageId, '👍');
      await pumpEventQueue();

      expect(reactions(timeline).single.status.isSent, true);
    });

    test('discards a rejected reaction and tells its listeners', () async {
      final rejecting = room(
        powerLevels: RoomDefaults.restrictedPowerLevelsContent,
        id: rejectingRoomId,
      );
      final timeline = await rejecting.getTimeline();
      final reactionCounts = <int>[];
      final listener = ReactionListener(
        event: Event(
          type: EventTypes.Message,
          content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
          senderId: ownUserId,
          eventId: messageId,
          originServerTs: DateTime.now(),
          room: rejecting,
        ),
        onUpdate: () => reactionCounts.add(reactions(timeline).length),
      );
      addTearDown(listener.dispose);

      await rejecting.sendReactionOrDiscard(messageId, '👍');
      await pumpEventQueue();

      expect(timeline.events, isEmpty);
      expect(reactionCounts.first, 1, reason: 'the echo shows while sending');
      expect(reactionCounts.last, 0);
    });
  });
}
