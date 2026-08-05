import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/knocked_rooms_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/utils/chat_list_handle_space_tap.dart';
import 'get_test_client.dart';

/// Two of the three space-invite outcomes in joining-courses.instructions.md
/// — "child of a joined parent" and "previously knocked" — join without ever
/// asking the user. A knock the learner sent must never come back looking like
/// an unsolicited invite, so this is load-bearing: an invite that stops being
/// auto-accepted is a regression, not a fix (see #7792, where the chat list
/// dropped the accepting instead of dropping the navigation that followed it).
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const invitedSpaceId = '!invited:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Event stateEvent(
    Room room, {
    required String type,
    required Map<String, dynamic> content,
    String stateKey = '',
  }) => Event(
    type: type,
    content: content,
    stateKey: stateKey,
    senderId: userId,
    eventId: '\$${type}_$stateKey',
    originServerTs: DateTime.now(),
    room: room,
  );

  Room space(String id, {required Membership membership, String? childId}) {
    final room = Room(id: id, client: client, membership: membership);
    room.setState(
      stateEvent(
        room,
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
      ),
    );
    if (childId != null) {
      room.setState(
        stateEvent(
          room,
          type: EventTypes.SpaceChild,
          content: {
            'via': ['fakeServer.notExisting'],
          },
          stateKey: childId,
        ),
      );
    }
    client.rooms.add(room);
    return room;
  }

  void recordKnock(String roomId) {
    client.accountData[PangeaEventTypes.knockedRooms] = BasicEvent(
      type: PangeaEventTypes.knockedRooms,
      content: KnockedRoomsModel(knockedRoomIds: [roomId]).toJson(),
    );
  }

  test('an invite the user never knocked on is not auto-accepted', () {
    final invited = space(invitedSpaceId, membership: Membership.invite);
    expect(SpaceTapUtil.isAutoAcceptedInvite(invited), isFalse);
  });

  test('an approved knock is auto-accepted', () {
    final invited = space(invitedSpaceId, membership: Membership.invite);
    recordKnock(invitedSpaceId);
    expect(SpaceTapUtil.isAutoAcceptedInvite(invited), isTrue);
  });

  test('an invite to a child of a joined course is auto-accepted', () {
    final invited = space(invitedSpaceId, membership: Membership.invite);
    space(
      '!parent:fakeServer.notExisting',
      membership: Membership.join,
      childId: invitedSpaceId,
    );
    expect(SpaceTapUtil.isAutoAcceptedInvite(invited), isTrue);
  });

  test('a child of a course the user has not joined is not auto-accepted', () {
    final invited = space(invitedSpaceId, membership: Membership.invite);
    space(
      '!parent:fakeServer.notExisting',
      membership: Membership.invite,
      childId: invitedSpaceId,
    );
    expect(SpaceTapUtil.isAutoAcceptedInvite(invited), isFalse);
  });

  test('a knock recorded for another room does not leak across invites', () {
    final invited = space(invitedSpaceId, membership: Membership.invite);
    recordKnock('!other:fakeServer.notExisting');
    expect(SpaceTapUtil.isAutoAcceptedInvite(invited), isFalse);
  });
}
