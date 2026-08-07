import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/widgets/invited_course_badge.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import '../get_test_client.dart';

/// The signal behind the Courses tab's invite badge on one column (#8190).
/// The web rail shows a pending course invite as the invited course's own
/// badged avatar; the narrow rail has no per-course avatars, so the tab wears
/// the badge — and it must light for exactly the courses `sortedCourses` puts
/// at the top of the hub list, no more.
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room space(String id, {required Membership membership}) {
    final room = Room(id: id, client: client, membership: membership);
    room.setState(
      Event(
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
        stateKey: '',
        senderId: userId,
        eventId: '\$create_$id',
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        room: room,
      ),
    );
    client.rooms.add(room);
    return room;
  }

  Room chat(String id, {required Membership membership}) {
    final room = Room(id: id, client: client, membership: membership);
    client.rooms.add(room);
    return room;
  }

  test('no rooms at all: no badge', () {
    expect(client.hasInvitedCourse, isFalse);
  });

  test('an invited course lights the badge', () {
    space('!invited:fakeServer.notExisting', membership: Membership.invite);
    expect(client.hasInvitedCourse, isTrue);
  });

  test('joined courses alone do not light the badge', () {
    space('!joined:fakeServer.notExisting', membership: Membership.join);
    expect(client.hasInvitedCourse, isFalse);
  });

  test('an invite to a plain chat is not a course invite', () {
    chat('!dm:fakeServer.notExisting', membership: Membership.invite);
    expect(client.hasInvitedCourse, isFalse);
  });

  test('a left course does not light the badge', () {
    space('!left:fakeServer.notExisting', membership: Membership.leave);
    expect(client.hasInvitedCourse, isFalse);
  });

  test('one invite among joined courses still lights the badge', () {
    space('!joined:fakeServer.notExisting', membership: Membership.join);
    space('!other:fakeServer.notExisting', membership: Membership.join);
    space('!invited:fakeServer.notExisting', membership: Membership.invite);
    expect(client.hasInvitedCourse, isTrue);
  });

  // On the rail the badge is the ONLY sign of the invite — no "Invited" pill
  // beside it, as the hub tile has — so a screen reader has to get it from the
  // badge itself.
  testWidgets('the badge announces itself when given a label', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InvitedCourseBadge(
            semanticLabel: 'Invited',
            child: Icon(Icons.map_outlined),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Invited'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('and stays silent without one, for labeled tiles', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InvitedCourseBadge(child: Icon(Icons.map_outlined)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Invited'), findsNothing);
    semantics.dispose();
  });

  // A hidden badge stays mounted (it fades in and out), so silencing it is a
  // real requirement, not a side effect of it being gone.
  testWidgets('a hidden badge announces nothing', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InvitedCourseBadge(
            showBadge: false,
            semanticLabel: 'Invited',
            child: Icon(Icons.map_outlined),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Invited'), findsNothing);
    semantics.dispose();
  });
}
