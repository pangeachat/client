import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

void main() {
  AppSection section(String location) => sectionFor(Uri.parse(location));
  String? space(String location) => activeSpaceIdFor(Uri.parse(location));

  group('sectionFor', () {
    test('root selects world; matrix rooms select chats', () {
      expect(section('/'), AppSection.world);
      expect(section('/chats'), AppSection.chats);
      expect(section('/rooms/!abc:server.org'), AppSection.chats);
    });

    test('section roots select themselves; a course room stays in courses', () {
      expect(section('/analytics'), AppSection.analytics);
      expect(section('/analytics/vocab/abc'), AppSection.analytics);
      expect(section('/courses'), AppSection.courses);
      // The nested course chat room is still the courses section, not chats —
      // the split this rebuild fixes.
      expect(section('/courses/!s:x/!room:x'), AppSection.courses);
      expect(section('/settings/security'), AppSection.settings);
      expect(section('/profile'), AppSection.profile);
    });

    test('first-class world objects (uuid) select world', () {
      expect(section('/32ad3c08-e501-41c5-b544-0875026090ed'), AppSection.world);
    });

    test('exact segments only — no substring leakage', () {
      expect(section('/courses/analytics-course-name'), AppSection.courses);
    });
  });

  group('activeSpaceIdFor', () {
    test('joined course spaces are detected (root, detail, overlay, room)', () {
      expect(space('/courses/!s:x'), '!s:x');
      expect(space('/courses/!s:x/details'), '!s:x');
      expect(space('/courses/!s:x?activity=a'), '!s:x');
      expect(space('/courses/!s:x/!room:x'), '!s:x');
    });

    test('literal course flows and preview are not space ids', () {
      expect(space('/courses/own'), isNull);
      expect(space('/courses'), isNull);
      // preview's room id must never masquerade as the active space.
      expect(space('/courses/preview/!r:x'), isNull);
    });
  });

  group('isMapHole', () {
    test('world is always the map hole, in both modes', () {
      expect(isMapHole('/', false), isTrue);
      expect(isMapHole('/', true), isTrue);
    });

    test('section roots are map holes in column mode only', () {
      expect(isMapHole('/chats', true), isTrue);
      expect(isMapHole('/chats', false), isFalse);
      expect(isMapHole('/courses/:spaceid', true), isTrue);
      expect(isMapHole('/analytics/morph', true), isTrue);
    });

    test('the add-course hub and detail routes are not map holes', () {
      expect(isMapHole('/courses', true), isFalse); // full-bleed
      expect(isMapHole('/courses/:spaceid/:roomid', true), isFalse); // detail
      expect(isMapHole('/rooms/:roomid', true), isFalse); // detail
    });
  });

  group('shortRoomId / fullRoomId (URL display)', () {
    const domain = 'local.pangea.chat';

    test('round-trips a home-domain id to a bare localpart', () {
      const full = '!GLEFhPQklmQQYWYiWc:local.pangea.chat';
      final short = shortRoomId(full, domain: domain);
      expect(short, '!GLEFhPQklmQQYWYiWc');
      expect(fullRoomId(short, domain: domain), full);
    });

    test('leaves foreign-homeserver ids untouched (federation-safe)', () {
      const foreign = '!abc:matrix.org';
      expect(shortRoomId(foreign, domain: domain), foreign);
      expect(fullRoomId(foreign, domain: domain), foreign);
    });

    test('fullRoomId is a no-op on an id that already carries a domain', () {
      expect(
        fullRoomId('!x:local.pangea.chat', domain: domain),
        '!x:local.pangea.chat',
      );
    });

    test('helpers degrade gracefully when the home domain is unknown', () {
      // Pre-login / no global: ids pass through unchanged rather than throwing.
      expect(shortRoomId('!x:local.pangea.chat'), '!x:local.pangea.chat');
      expect(fullRoomId('!x'), '!x');
    });

    test('shortenHomeRoomIdsInUrl strips home domain across path + query', () {
      const d = 'local.pangea.chat';
      expect(
        shortenHomeRoomIdsInUrl('/rooms/!abc:local.pangea.chat', domain: d),
        '/rooms/!abc',
      );
      expect(
        shortenHomeRoomIdsInUrl('/rooms/!abc:local.pangea.chat/details', domain: d),
        '/rooms/!abc/details',
      );
      expect(
        shortenHomeRoomIdsInUrl(
          '/courses/!s:local.pangea.chat?activity=x&roomid=!r:local.pangea.chat',
          domain: d,
        ),
        '/courses/!s?activity=x&roomid=!r',
      );
      // Foreign-homeserver ids keep their domain (federation-safe).
      expect(
        shortenHomeRoomIdsInUrl('/rooms/!abc:matrix.org', domain: d),
        '/rooms/!abc:matrix.org',
      );
    });
  });
}
