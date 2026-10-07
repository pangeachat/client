import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'get_test_client.dart';

/// #9364 — a session the admin dashboard joined a teacher to, only so they
/// could read it, stays out of their chat lists until they take a role in it,
/// and leaving the course leaves it.
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const spaceId = '!course:fakeServer.notExisting';
  const reviewRoomId = '!review:fakeServer.notExisting';
  const archivedRoomId = '!archived:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  void listForReview(List<String> roomIds) {
    client.accountData[PangeaEventTypes.adminReviewRooms] = BasicEvent(
      type: PangeaEventTypes.adminReviewRooms,
      content: {'room_ids': roomIds},
    );
  }

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
    originServerTs: DateTime.utc(2026, 1, 1),
    room: room,
  );

  Room session(String id, {ActivityRoleModel? ownRole}) {
    final room = Room(id: id, client: client, membership: Membership.join);
    if (ownRole != null) {
      room.setState(
        stateEvent(
          room,
          type: PangeaEventTypes.activityRole,
          content: ActivityRolesModel({ownRole.id: ownRole}).toJson(),
        ),
      );
    }
    client.rooms.add(room);
    return room;
  }

  ActivityRoleModel ownRole({DateTime? archivedAt}) =>
      ActivityRoleModel(id: 'role-1', userId: userId, archivedAt: archivedAt);

  test('a listed session the teacher has no role in is hidden', () {
    listForReview([reviewRoomId]);
    final room = session(reviewRoomId);

    expect(room.isAdminReviewOnly, isTrue);
    expect(room.isHiddenRoom, isTrue);
  });

  test('taking a role brings a listed session back', () {
    listForReview([reviewRoomId]);
    final room = session(reviewRoomId, ownRole: ownRole());

    expect(room.isAdminReviewOnly, isFalse);
    expect(room.isHiddenRoom, isFalse);
  });

  test('a session missing from the list is not hidden', () {
    listForReview(['!other:fakeServer.notExisting']);
    expect(session(reviewRoomId).isHiddenRoom, isFalse);

    client.accountData.remove(PangeaEventTypes.adminReviewRooms);
    expect(session(reviewRoomId).isHiddenRoom, isFalse);
  });

  test(
    'leaving the course leaves a review room but keeps an archived one',
    () async {
      listForReview([reviewRoomId]);
      session(reviewRoomId);
      session(archivedRoomId, ownRole: ownRole(archivedAt: DateTime.utc(2026)));
      final space = Room(id: spaceId, client: client);
      space.setState(
        stateEvent(
          space,
          type: EventTypes.RoomCreate,
          content: {'type': RoomCreationTypes.mSpace},
        ),
      );
      for (final childId in [reviewRoomId, archivedRoomId]) {
        space.setState(
          stateEvent(
            space,
            type: EventTypes.SpaceChild,
            content: {
              'via': ['fakeServer.notExisting'],
            },
            stateKey: childId,
          ),
        );
      }

      FakeMatrixApi.calledEndpoints.clear();
      await space.leaveSpace();

      bool left(String roomId) => FakeMatrixApi.calledEndpoints.keys.any(
        (path) =>
            path.contains(Uri.encodeComponent(roomId)) &&
            path.endsWith('/leave'),
      );
      expect(left(reviewRoomId), isTrue);
      expect(left(archivedRoomId), isFalse);
    },
  );
}
