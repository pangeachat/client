import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/joined_target.dart';

/// [JoinedTarget.fromRoomState] — the landing-target resolution for a joined
/// room sync has not yet surfaced (#8047), over raw `GET /rooms/{id}/state`
/// events. Must mirror [JoinedTargetRoomExtension.joinedTarget]: space →
/// course, activity session → activity page, coded chat under a joined
/// course → that course, anything else → the room.
void main() {
  const roomId = '!session:example.com';
  const courseId = '!course:example.com';

  MatrixEvent state(
    String type,
    Map<String, Object?> content, {
    String stateKey = '',
  }) => MatrixEvent(
    type: type,
    content: content,
    senderId: '@alice:example.com',
    stateKey: stateKey,
    eventId: '\$event:example.com',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
  );

  MatrixEvent createEvent(String? roomType) =>
      state(EventTypes.RoomCreate, roomType == null ? {} : {'type': roomType});

  Map<String, Object?> embeddedPlanContent({required String idKey}) => {
    idKey: 'legacy-activity',
    'req': {
      'topic': 'Ordering food',
      'mode': 'discussion',
      'objective': 'Practice ordering a meal',
      'media': 'nan',
      'language_of_instructions': 'en',
      'target_language': 'es',
      'count': 1,
      'number_of_participants': 2,
    },
    'title': 'Ordering food',
    'learning_objective': 'Practice ordering a meal',
    'instructions': 'Order a meal at the cafe.',
    'vocab': <Object?>[],
  };

  bool noJoinedSpaces(String _) => false;

  test('a space resolves to itself as a course', () {
    final target = JoinedTarget.fromRoomState(roomId, [
      createEvent('m.space'),
    ], noJoinedSpaces);
    expect(target, const JoinedTarget.course(roomId));
  });

  test('a v3 activity session resolves the id from the room-type suffix', () {
    final target = JoinedTarget.fromRoomState(roomId, [
      createEvent('p.activity.session:abc-123'),
    ], noJoinedSpaces);
    expect(target, const JoinedTarget.activitySession(roomId, 'abc-123'));
  });

  test('a legacy embedded plan resolves the id from state', () {
    final target = JoinedTarget.fromRoomState(roomId, [
      createEvent(null),
      state('pangea.activity_plan', embeddedPlanContent(idKey: 'activity_id')),
    ], noJoinedSpaces);
    expect(
      target,
      const JoinedTarget.activitySession(roomId, 'legacy-activity'),
    );
  });

  test('a deprecated (bookmark) embedded plan is not a session', () {
    final target = JoinedTarget.fromRoomState(roomId, [
      createEvent(null),
      state('pangea.activity_plan', embeddedPlanContent(idKey: 'bookmark_id')),
    ], noJoinedSpaces);
    expect(target, const JoinedTarget.room(roomId));
  });

  test('a chat under a locally-joined course resolves to the course', () {
    final target = JoinedTarget.fromRoomState(roomId, [
      createEvent(null),
      state(EventTypes.SpaceParent, {
        'via': ['example.com'],
      }, stateKey: courseId),
    ], (id) => id == courseId);
    expect(target, const JoinedTarget.course(courseId));
  });

  test('a parent without via, or not locally joined, is ignored', () {
    for (final parent in [
      // Spec-invalid parent: no via — must be skipped even though joined.
      state(EventTypes.SpaceParent, {}, stateKey: courseId),
      // Valid parent the joiner is not in (the no-shared-course invitee).
      state(EventTypes.SpaceParent, {
        'via': ['example.com'],
      }, stateKey: '!other:example.com'),
    ]) {
      final target = JoinedTarget.fromRoomState(roomId, [
        createEvent(null),
        parent,
      ], (id) => id == courseId);
      expect(target, const JoinedTarget.room(roomId));
    }
  });

  test('an unrecognized room resolves to itself as a room, not a course', () {
    final target = JoinedTarget.fromRoomState(roomId, [], noJoinedSpaces);
    expect(target, const JoinedTarget.room(roomId));
  });
}
