import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/space_code_controller.dart';

/// [SpaceCodeController.resolveTargetFromRoomState] — the landing-target
/// resolution for a joined room sync has not yet surfaced (#8047), over raw
/// `GET /rooms/{id}/state` events. Must mirror the local-room branches of
/// `resolveJoinedTarget`: space → course, activity session → activity page,
/// coded chat under a joined course → that course, anything else → the room.
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
    final target = SpaceCodeController.resolveTargetFromRoomState(roomId, [
      createEvent('m.space'),
    ], noJoinedSpaces);
    expect(target, (roomId: roomId, isSpace: true, activityId: null));
  });

  test('a v3 activity session resolves the id from the room-type suffix', () {
    final target = SpaceCodeController.resolveTargetFromRoomState(roomId, [
      createEvent('p.activity.session:abc-123'),
    ], noJoinedSpaces);
    expect(target, (roomId: roomId, isSpace: false, activityId: 'abc-123'));
  });

  test('a legacy embedded plan resolves the id from state', () {
    final target = SpaceCodeController.resolveTargetFromRoomState(roomId, [
      createEvent(null),
      state('pangea.activity_plan', embeddedPlanContent(idKey: 'activity_id')),
    ], noJoinedSpaces);
    expect(target, (
      roomId: roomId,
      isSpace: false,
      activityId: 'legacy-activity',
    ));
  });

  test('a deprecated (bookmark) embedded plan is not a session', () {
    final target = SpaceCodeController.resolveTargetFromRoomState(roomId, [
      createEvent(null),
      state('pangea.activity_plan', embeddedPlanContent(idKey: 'bookmark_id')),
    ], noJoinedSpaces);
    expect(target, (roomId: roomId, isSpace: false, activityId: null));
  });

  test('a chat under a locally-joined course resolves to the course', () {
    final target = SpaceCodeController.resolveTargetFromRoomState(roomId, [
      createEvent(null),
      state(EventTypes.SpaceParent, {
        'via': ['example.com'],
      }, stateKey: courseId),
    ], (id) => id == courseId);
    expect(target, (roomId: courseId, isSpace: true, activityId: null));
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
      final target = SpaceCodeController.resolveTargetFromRoomState(roomId, [
        createEvent(null),
        parent,
      ], (id) => id == courseId);
      expect(target, (roomId: roomId, isSpace: false, activityId: null));
    }
  });

  test('an unrecognized room resolves to itself as a room, not a course', () {
    final target = SpaceCodeController.resolveTargetFromRoomState(
      roomId,
      [],
      noJoinedSpaces,
    );
    expect(target, (roomId: roomId, isSpace: false, activityId: null));
  });
}
