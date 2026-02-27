import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/join_codes/knock_notification_utils.dart';

void main() {
  const roomId = '!course:staging.pangea.chat';
  const userId = '@learner:staging.pangea.chat';
  const adminId = '@teacher:staging.pangea.chat';

  group('isKnockAcceptedInvite', () {
    test('returns true when all conditions match a knock-accepted invite', () {
      final result = isKnockAcceptedInvite(
        eventType: EventTypes.RoomMember,
        newMembership: 'invite',
        stateKey: userId,
        currentUserId: userId,
        knockedRoomIds: [roomId],
        roomId: roomId,
      );
      expect(result, isTrue);
    });

    test('returns false when event is not m.room.member', () {
      final result = isKnockAcceptedInvite(
        eventType: 'm.room.message',
        newMembership: 'invite',
        stateKey: userId,
        currentUserId: userId,
        knockedRoomIds: [roomId],
        roomId: roomId,
      );
      expect(result, isFalse);
    });

    test('returns false when membership is not invite (e.g. join)', () {
      final result = isKnockAcceptedInvite(
        eventType: EventTypes.RoomMember,
        newMembership: 'join',
        stateKey: userId,
        currentUserId: userId,
        knockedRoomIds: [roomId],
        roomId: roomId,
      );
      expect(result, isFalse);
    });

    test('returns false when membership is null', () {
      final result = isKnockAcceptedInvite(
        eventType: EventTypes.RoomMember,
        newMembership: null,
        stateKey: userId,
        currentUserId: userId,
        knockedRoomIds: [roomId],
        roomId: roomId,
      );
      expect(result, isFalse);
    });

    test('returns false when invite targets a different user (not current user)',
        () {
      final result = isKnockAcceptedInvite(
        eventType: EventTypes.RoomMember,
        newMembership: 'invite',
        stateKey: adminId, // <-- someone else was invited
        currentUserId: userId,
        knockedRoomIds: [roomId],
        roomId: roomId,
      );
      expect(result, isFalse);
    });

    test('returns false when stateKey is null', () {
      final result = isKnockAcceptedInvite(
        eventType: EventTypes.RoomMember,
        newMembership: 'invite',
        stateKey: null,
        currentUserId: userId,
        knockedRoomIds: [roomId],
        roomId: roomId,
      );
      expect(result, isFalse);
    });

    test('returns false when the room was not previously knocked on', () {
      final result = isKnockAcceptedInvite(
        eventType: EventTypes.RoomMember,
        newMembership: 'invite',
        stateKey: userId,
        currentUserId: userId,
        knockedRoomIds: [], // <-- no prior knock recorded
        roomId: roomId,
      );
      expect(result, isFalse);
    });

    test('returns false when a different room was knocked', () {
      final result = isKnockAcceptedInvite(
        eventType: EventTypes.RoomMember,
        newMembership: 'invite',
        stateKey: userId,
        currentUserId: userId,
        knockedRoomIds: ['!other:staging.pangea.chat'],
        roomId: roomId,
      );
      expect(result, isFalse);
    });

    test('handles multiple knocked rooms and matches the correct one', () {
      final result = isKnockAcceptedInvite(
        eventType: EventTypes.RoomMember,
        newMembership: 'invite',
        stateKey: userId,
        currentUserId: userId,
        knockedRoomIds: [
          '!other1:staging.pangea.chat',
          roomId,
          '!other2:staging.pangea.chat',
        ],
        roomId: roomId,
      );
      expect(result, isTrue);
    });
  });
}
