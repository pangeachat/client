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

    test('an active ?m=course filter selects courses (path is /)', () {
      // world_v2: a course is a map filter, so it selects the Courses section
      // even though the path is the world map and panels are independent.
      expect(section('/?m=course:!s:x'), AppSection.courses);
      expect(section('/?left=room:!r&m=course:!s:x'), AppSection.courses);
    });

    test('section identity rides in the left token at the world path /', () {
      // The path collapses to `/`; the rail highlight derives from the token.
      expect(section('/?left=chats'), AppSection.chats);
      expect(section('/?left=chats,room:!a'), AppSection.chats);
      expect(section('/?left=room:!a'), AppSection.chats); // a lone live chat
      expect(section('/?left=addcourse'), AppSection.courses); // the hub
      expect(section('/?left=addcourse:own'), AppSection.courses); // a step
    });
  });

  group('activeSpaceIdFor (course is the ?m= map filter, not the path)', () {
    test('reads the course filter from ?m=, anywhere in the query', () {
      expect(space('/?m=course:!s:x'), '!s:x');
      expect(space('/?m=course:%21abc'), '!abc'); // an encoded param decodes
      // independent of the path and of which panels happen to be open
      expect(
        space('/?left=room:!r&m=course:!s:x&right=analytics:vocab'),
        '!s:x',
      );
    });

    test('no course filter → null (world map)', () {
      expect(space('/'), isNull);
      expect(space('/?left=room:!r'), isNull); // a room token is not a course
      expect(space('/?m=region:europe'), isNull); // a non-course filter
      // the legacy path no longer carries the space id (it redirects to ?m=).
      expect(space('/courses/!s:x'), isNull);
    });
  });

  group('isMapHole (world_v2: only the world root is a map hole)', () {
    test('the world root is the map hole', () {
      expect(isMapHole('/'), isTrue);
    });

    test('every other route renders content, never a hole', () {
      // Every section is a token panel now — there are no /chats, /settings,
      // /analytics, or /profile render routes — so no path but `/` is a hole.
      // The remaining real routes are bounded details or full-bleed.
      expect(isMapHole('/settings'), isFalse);
      expect(isMapHole('/analytics/morph'), isFalse);
      expect(isMapHole('/courses'), isFalse);
      expect(isMapHole('/practice/vocab'), isFalse);
      expect(isMapHole('/rooms/archive/abc'), isFalse);
      expect(isMapHole(null), isFalse);
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
