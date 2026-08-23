import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/pangea/spaces/course_role_groups.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import '../get_test_client.dart';

/// Coverage for #8425: the Courses hub and the nav rail split the learner's
/// courses by role — invited, teaching (course admin), learning — but only
/// when the learner actually holds both roles. Otherwise the order must be
/// exactly what it was: invites first, then joined courses alphabetically.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late L10n l10n;

  const userId = '@test:fakeServer.notExisting';

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

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
    eventId: '\$${type}_${room.id}_$stateKey',
    originServerTs: DateTime.now(),
    room: room,
  );

  /// A course space named [name] the viewer holds [ownPowerLevel] in, joined
  /// unless [invited].
  Room course(String name, {int ownPowerLevel = 0, bool invited = false}) {
    final room = Room(
      id: '!${name.replaceAll(' ', '')}:fakeServer.notExisting',
      client: client,
      membership: invited ? Membership.invite : Membership.join,
    );
    room.setState(
      stateEvent(
        room,
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
      ),
    );
    room.setState(
      stateEvent(room, type: EventTypes.RoomName, content: {'name': name}),
    );
    room.setState(
      stateEvent(
        room,
        type: EventTypes.RoomPowerLevels,
        content: {
          ...RoomDefaults.defaultPowerLevelsContent(),
          'users': {userId: ownPowerLevel},
        },
      ),
    );
    client.rooms.add(room);
    return room;
  }

  List<String> names(List<Room> rooms) => rooms
      .map((r) => r.getState(EventTypes.RoomName)!.content['name'] as String)
      .toList();

  test('splits by role, alphabetical within each group', () {
    course('Korean Basics');
    course('Deutsch A1', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);
    course('Português', invited: true);
    course('Español 2', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);
    course('Arabic Alphabet');

    final groups = client.coursesByRole(l10n);

    expect(names(groups.invited), ['Português']);
    expect(names(groups.teaching), ['Deutsch A1', 'Español 2']);
    expect(names(groups.learning), ['Arabic Alphabet', 'Korean Basics']);
    expect(groups.isGrouped, isTrue);
    expect(groups.courseCount, 5);
    expect(groups.sectionCount, 3, reason: 'invited + teaching + learning');
    expect(groups.sections.map((s) => s.group), [
      CourseRoleGroup.invited,
      CourseRoleGroup.teaching,
      CourseRoleGroup.learning,
    ]);
    expect(
      names(groups.ordered),
      [
        'Português',
        'Deutsch A1',
        'Español 2',
        'Arabic Alphabet',
        'Korean Basics',
      ],
      reason: 'display order is invited · teaching · learning',
    );
  });

  test('a pure learner is not grouped and keeps the old order', () {
    course('Korean Basics');
    course('Português', invited: true);
    course('Arabic Alphabet');

    final groups = client.coursesByRole(l10n);

    expect(groups.isGrouped, isFalse);
    expect(groups.sectionCount, 0, reason: 'no headers for a single role');
    expect(
      names(groups.ordered),
      names(client.sortedCourses(l10n)),
      reason: 'invites first, then alphabetical — unchanged from before',
    );
  });

  test('a pure teacher is not grouped either', () {
    course('Deutsch A1', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);
    course('Español 2', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);

    final groups = client.coursesByRole(l10n);

    expect(groups.isGrouped, isFalse);
    expect(groups.sectionCount, 0);
    expect(names(groups.ordered), ['Deutsch A1', 'Español 2']);
  });

  test('an invite is never counted as teaching, even at admin power', () {
    // Power levels are not part of stripped invite state in practice, but if
    // one is present the invite still belongs to the invited group: its role
    // is unknown until join.
    course(
      'Português',
      invited: true,
      ownPowerLevel: SpaceConstants.powerLevelOfAdmin,
    );
    course('Korean Basics');
    course('Deutsch A1', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);

    final groups = client.coursesByRole(l10n);

    expect(names(groups.invited), ['Português']);
    expect(names(groups.teaching), ['Deutsch A1']);
    expect(names(groups.learning), ['Korean Basics']);
    expect(groups.sectionCount, 3);
  });

  test('section titles resolve through l10n', () {
    expect(CourseRoleGroup.invited.title(l10n), l10n.invited);
    expect(CourseRoleGroup.teaching.title(l10n), l10n.courseSectionTeaching);
    expect(CourseRoleGroup.learning.title(l10n), l10n.courseSectionLearning);
  });
}
