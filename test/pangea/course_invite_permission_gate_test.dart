import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'get_test_client.dart';

/// Courses are created with `invite: 50` ([RoomDefaults.defaultPowerLevelsContent]),
/// so an ordinary learner (PL 0) cannot invite anyone to the course. The
/// activity start page's "Invite friends to my course" CTA — offered when a
/// 3-or-4-person activity doesn't have enough coursemates — is gated on
/// `course.canInvite` for exactly that reason: without the power level the
/// invite page only produces errors (#7875).
///
/// This pins the input to that gate: the course's own defaults, plus the
/// membership requirement (a learner who hasn't joined can't invite either).
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room courseRoom({
    required int ownPowerLevel,
    Membership membership = Membership.join,
  }) {
    final room = Room(
      id: '!course:fakeServer.notExisting',
      client: client,
      membership: membership,
    );
    room.setState(
      Event(
        type: EventTypes.RoomPowerLevels,
        content: {
          ...RoomDefaults.defaultPowerLevelsContent(),
          'users': {userId: ownPowerLevel},
        },
        stateKey: '',
        senderId: userId,
        eventId: '\$powerLevels',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
    return room;
  }

  test('a learner at the default power level cannot invite to a course', () {
    expect(courseRoom(ownPowerLevel: 0).canInvite, false);
  });

  test('a teacher/admin can invite to a course', () {
    expect(courseRoom(ownPowerLevel: 50).canInvite, true);
    expect(courseRoom(ownPowerLevel: 100).canInvite, true);
  });

  test('an un-joined user cannot invite, whatever the power levels say', () {
    expect(
      courseRoom(ownPowerLevel: 100, membership: Membership.invite).canInvite,
      false,
    );
  });
}
