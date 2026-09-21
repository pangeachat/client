import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/widgets/layouts/workspace_shell.dart';
import '../get_test_client.dart';

/// Regression coverage for #8599: the narrow rail's course-shortcut slot must
/// track the LIVE joined-course set. Deleting a course removes it from the
/// joined set via sync, and the resolution — and the fingerprint that gates
/// the shell's sync-driven rebuild — must reflect that immediately, instead of
/// showing the deleted course until the next route-driven rebuild.
///
/// Drives the production resolver ([resolveCourseShortcut]) and fingerprint
/// ([courseShortcutFingerprint]) in `workspace_shell.dart` directly; the
/// StreamBuilder wiring rebuilds exactly when the fingerprint changes
/// (`distinct()`), so fingerprint equality IS the rebuild contract.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const courseAId = '!course-a:fakeServer.notExisting';
  const courseBId = '!course-b:fakeServer.notExisting';

  late Client client;

  setUp(() async {
    resetCourseShortcutMemoryForTest();
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room joinedSpace(String id, {required String name}) {
    final space = Room(id: id, client: client, membership: Membership.join);
    space.setState(
      Event(
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
        stateKey: '',
        senderId: userId,
        eventId: '\$create_$id',
        originServerTs: DateTime.utc(2026, 1, 1),
        room: space,
      ),
    );
    space.setState(
      Event(
        type: EventTypes.RoomName,
        content: {'name': name},
        stateKey: '',
        senderId: userId,
        eventId: '\$name_$id',
        originServerTs: DateTime.utc(2026, 1, 1),
        room: space,
      ),
    );
    client.rooms.add(space);
    return space;
  }

  group('resolveCourseShortcut', () {
    test('no joined courses resolves to null (the + button)', () {
      expect(resolveCourseShortcut(client, activeSpaceId: null), isNull);
      expect(courseShortcutFingerprint(null), '');
    });

    test('remembers the active course and keeps it once inactive', () {
      joinedSpace(courseAId, name: 'Course A');
      joinedSpace(courseBId, name: 'Course B');

      // Opening course B records it as most recent...
      expect(
        resolveCourseShortcut(client, activeSpaceId: courseBId)?.id,
        courseBId,
      );
      // ...and it stays the shortcut after the scope leaves it.
      expect(resolveCourseShortcut(client, activeSpaceId: null)?.id, courseBId);
    });

    test('a deleted course leaves the slot immediately (#8599)', () {
      joinedSpace(courseAId, name: 'Course A');
      final courseB = joinedSpace(courseBId, name: 'Course B');

      resolveCourseShortcut(client, activeSpaceId: courseBId);

      // The delete's marked self-leave arrives via sync: B is no longer
      // joined, so the slot must fall back to a course that still is.
      courseB.membership = Membership.leave;
      expect(resolveCourseShortcut(client, activeSpaceId: null)?.id, courseAId);
    });
  });

  group('courseShortcutFingerprint — the rebuild gate', () {
    test('is stable while nothing the slot renders changes', () {
      joinedSpace(courseAId, name: 'Course A');
      final first = courseShortcutFingerprint(
        resolveCourseShortcut(client, activeSpaceId: courseAId),
      );
      final second = courseShortcutFingerprint(
        resolveCourseShortcut(client, activeSpaceId: courseAId),
      );
      // distinct() suppresses these — no rebuild on an unrelated sync.
      expect(second, first);
    });

    test('changes when the resolved course changes (#8599)', () {
      joinedSpace(courseAId, name: 'Course A');
      final courseB = joinedSpace(courseBId, name: 'Course B');

      final before = courseShortcutFingerprint(
        resolveCourseShortcut(client, activeSpaceId: courseBId),
      );
      courseB.membership = Membership.leave;
      final after = courseShortcutFingerprint(
        resolveCourseShortcut(client, activeSpaceId: null),
      );
      // distinct() lets this through — the deletion triggers the rebuild.
      expect(after, isNot(before));
    });

    test('changes when the shortcut course is renamed', () {
      final courseA = joinedSpace(courseAId, name: 'Course A');
      final before = courseShortcutFingerprint(
        resolveCourseShortcut(client, activeSpaceId: courseAId),
      );
      courseA.setState(
        Event(
          type: EventTypes.RoomName,
          content: {'name': 'Course A, renamed'},
          stateKey: '',
          senderId: userId,
          eventId: '\$rename_$courseAId',
          originServerTs: DateTime.utc(2026, 1, 2),
          room: courseA,
        ),
      );
      final after = courseShortcutFingerprint(
        resolveCourseShortcut(client, activeSpaceId: courseAId),
      );
      expect(after, isNot(before));
    });
  });
}
