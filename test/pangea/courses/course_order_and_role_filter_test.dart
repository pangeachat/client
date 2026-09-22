import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/pangea/spaces/course_role_filter.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_courses_list_view.dart';
import '../get_test_client.dart';

/// Coverage for the Courses hub's and the nav rail's one course order (#9004,
/// #9207): invites first, then every joined course by recent activity across
/// the space and its joined children, whatever the learner's role in it, with
/// ties and invites ordered by name. And for the hub's role filter pills
/// (#9207): which courses each pill keeps, and when the pills show at all.
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

  test('sorts joined courses by activity across roles, invites first', () {
    final korean = course('Korean Basics');
    final deutsch = course(
      'Deutsch A1',
      ownPowerLevel: SpaceConstants.powerLevelOfAdmin,
    );
    course('Português', invited: true);
    course('Español 2', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);
    course('Arabic Alphabet');
    childChat(korean, 'Korean chat', lastActivity: DateTime(2026, 3, 2));
    childChat(deutsch, 'Deutsch chat', lastActivity: DateTime(2026, 3, 1));

    expect(
      names(client.sortedCourses(l10n)),
      [
        'Português',
        'Korean Basics',
        'Deutsch A1',
        'Arabic Alphabet',
        'Español 2',
      ],
      reason: 'a learning course and a teaching course interleave by activity',
    );
  });

  test('a newer event in a child chat moves its course to the top', () {
    final arabic = course('Arabic Alphabet');
    final korean = course('Korean Basics');
    final deutsch = course(
      'Deutsch A1',
      ownPowerLevel: SpaceConstants.powerLevelOfAdmin,
    );
    childChat(arabic, 'Arabic chat', lastActivity: DateTime(2026, 3, 1));
    childChat(korean, 'Korean chat', lastActivity: DateTime(2026, 3, 2));
    childChat(deutsch, 'Deutsch chat', lastActivity: DateTime(2026, 3, 3));

    expect(names(client.sortedCourses(l10n)), [
      'Deutsch A1',
      'Korean Basics',
      'Arabic Alphabet',
    ]);

    // Activity arrives in the bottom course: the order re-sorts live.
    childChat(arabic, 'Arabic session', lastActivity: DateTime(2026, 3, 4));

    expect(names(client.sortedCourses(l10n)), [
      'Arabic Alphabet',
      'Deutsch A1',
      'Korean Basics',
    ]);
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

  group('CourseRoleFilter', () {
    test('teaching keeps joined admin courses, learning the rest', () {
      course('Korean Basics');
      course('Deutsch A1', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);
      course('Español 2', ownPowerLevel: 50);
      final courses = client.sortedCourses(l10n);

      expect(
        names(courses.where(CourseRoleFilter.teaching.includes).toList()),
        ['Deutsch A1'],
      );
      expect(
        names(courses.where(CourseRoleFilter.learning.includes).toList()),
        ['Español 2', 'Korean Basics'],
        reason: 'a moderator is not an admin, so it is a learning course',
      );
      expect(
        names(courses.where(CourseRoleFilter.all.includes).toList()),
        names(courses),
      );
    });

    test('an invite shows under All only, even at admin power', () {
      // Power levels are not part of stripped invite state in practice, but
      // if one is present the invite's role is still unknown until join.
      course(
        'Português',
        invited: true,
        ownPowerLevel: SpaceConstants.powerLevelOfAdmin,
      );
      final courses = client.sortedCourses(l10n);

      expect(courses.where(CourseRoleFilter.all.includes), hasLength(1));
      expect(courses.where(CourseRoleFilter.teaching.includes), isEmpty);
      expect(courses.where(CourseRoleFilter.learning.includes), isEmpty);
    });

    test('the pills show only when the learner holds both roles', () {
      course('Korean Basics');
      course('Português', invited: true);
      expect(
        CourseRoleFilter.appliesTo(client.sortedCourses(l10n)),
        isFalse,
        reason: 'a pure learner has nothing to filter',
      );

      course('Deutsch A1', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);
      expect(CourseRoleFilter.appliesTo(client.sortedCourses(l10n)), isTrue);
    });

    test('a pure teacher sees no pills either', () {
      course('Deutsch A1', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);
      course('Español 2', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);

      expect(CourseRoleFilter.appliesTo(client.sortedCourses(l10n)), isFalse);
    });

    test('labels reuse the Teaching / Learning strings', () {
      expect(CourseRoleFilter.all.label(l10n), l10n.all);
      expect(CourseRoleFilter.teaching.label(l10n), l10n.courseSectionTeaching);
      expect(CourseRoleFilter.learning.label(l10n), l10n.courseSectionLearning);
    });
  });

  group('LeftPanelCoursesListView.showsSearchBar', () {
    test('counts joined courses only, and needs more than four', () {
      for (final name in ['A', 'B', 'C', 'D']) {
        course(name);
      }
      course('Invited', invited: true);
      expect(
        LeftPanelCoursesListView.showsSearchBar(client.sortedCourses(l10n)),
        isFalse,
        reason: 'four joined courses plus an invite is not more than four',
      );

      course('E', ownPowerLevel: SpaceConstants.powerLevelOfAdmin);
      expect(
        LeftPanelCoursesListView.showsSearchBar(client.sortedCourses(l10n)),
        isTrue,
      );
    });
  });
}
