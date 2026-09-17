import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/pangea/spaces/course_role_groups.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import '../get_test_client.dart';

/// Coverage for #8425: the Courses hub and the nav rail split the learner's
/// courses by role — invited, teaching (course admin), learning — but only
/// when the learner actually holds both roles; otherwise the list is flat with
/// invites first. And for #9004: within that order, joined courses sort by
/// recent activity across the space and its joined children, with ties and
/// invites ordered by name.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late L10n l10n;

  const userId = '@test:fakeServer.notExisting';

  /// Every fixture event's timestamp unless a test sets activity, so courses
  /// tie on activity and fall back to name order.
  final setupTime = DateTime(2026, 1, 1);

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
    originServerTs: setupTime,
    room: room,
  );

  Event message(Room room, DateTime at) => Event(
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
    senderId: userId,
    eventId: '\$message_${room.id}_${at.millisecondsSinceEpoch}',
    originServerTs: at,
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

  /// A chat inside [parent] whose newest event is at [lastActivity].
  Room childChat(
    Room parent,
    String name, {
    required DateTime lastActivity,
    Membership membership = Membership.join,
    String? roomType,
  }) {
    final child = Room(
      id: '!${name.replaceAll(' ', '')}:fakeServer.notExisting',
      client: client,
      membership: membership,
    );
    if (roomType != null) {
      child.setState(
        stateEvent(
          child,
          type: EventTypes.RoomCreate,
          content: {'type': roomType},
        ),
      );
    }
    child.lastEvent = message(child, lastActivity);
    client.rooms.add(child);
    parent.setState(
      stateEvent(
        parent,
        type: EventTypes.SpaceChild,
        stateKey: child.id,
        content: {
          'via': ['fakeServer.notExisting'],
        },
      ),
    );
    return child;
  }

  List<String> names(List<Room> rooms) => rooms
      .map((r) => r.getState(EventTypes.RoomName)!.content['name'] as String)
      .toList();

  test('splits by role, by name within each group when activity ties', () {
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
      reason: 'the flat list is the same invites-first order',
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

  test('a newer event in a child chat moves its course up its group', () {
    final arabic = course('Arabic Alphabet');
    final korean = course('Korean Basics');
    final deutsch = course(
      'Deutsch A1',
      ownPowerLevel: SpaceConstants.powerLevelOfAdmin,
    );
    course('Español 2', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);
    childChat(arabic, 'Arabic chat', lastActivity: DateTime(2026, 3, 1));
    childChat(korean, 'Korean chat', lastActivity: DateTime(2026, 3, 2));
    childChat(deutsch, 'Deutsch chat', lastActivity: DateTime(2026, 2, 1));

    var groups = client.coursesByRole(l10n);

    expect(names(groups.learning), ['Korean Basics', 'Arabic Alphabet']);
    expect(
      names(groups.teaching),
      ['Deutsch A1', 'Español 2'],
      reason: 'grouping is kept: a teaching course never jumps into learning',
    );

    // Activity arrives in the bottom course: the order re-sorts live.
    childChat(arabic, 'Arabic session', lastActivity: DateTime(2026, 3, 3));
    groups = client.coursesByRole(l10n);

    expect(names(groups.learning), ['Arabic Alphabet', 'Korean Basics']);
  });

  test("the space's own newest event counts as activity", () {
    course('Arabic Alphabet');
    final korean = course('Korean Basics');
    korean.lastEvent = message(korean, DateTime(2026, 3, 1));

    expect(names(client.sortedCourses(l10n)), [
      'Korean Basics',
      'Arabic Alphabet',
    ]);
  });

  test('a child chat the learner has not joined is not activity', () {
    final arabic = course('Arabic Alphabet');
    course('Korean Basics');
    childChat(
      arabic,
      'Arabic invite',
      lastActivity: DateTime(2026, 3, 1),
      membership: Membership.invite,
    );

    expect(
      names(client.sortedCourses(l10n)),
      ['Arabic Alphabet', 'Korean Basics'],
      reason: 'no joined activity on either course, so name order',
    );
  });

  test('an analytics room child is not course activity', () {
    course('Arabic Alphabet');
    final korean = course('Korean Basics');
    childChat(
      korean,
      'Korean analytics',
      lastActivity: DateTime(2026, 3, 1),
      roomType: PangeaRoomTypes.analytics,
    );

    expect(
      names(client.sortedCourses(l10n)),
      ['Arabic Alphabet', 'Korean Basics'],
      reason: 'a shared analytics room would move every course it sits in',
    );
  });

  test('invites carry no activity and stay ordered by name', () {
    course('Korean Basics');
    course('Português', invited: true);
    course('Deutsch', invited: true);

    expect(names(client.sortedCourses(l10n)), [
      'Deutsch',
      'Português',
      'Korean Basics',
    ]);
  });

  test('section titles resolve through l10n', () {
    expect(CourseRoleGroup.invited.title(l10n), l10n.invited);
    expect(CourseRoleGroup.teaching.title(l10n), l10n.courseSectionTeaching);
    expect(CourseRoleGroup.learning.title(l10n), l10n.courseSectionLearning);
  });
}
