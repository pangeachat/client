import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/legacy_redirects.dart';

void main() {
  String? resolve(String location) =>
      LegacyRedirects.resolve(Uri.parse(location));

  group('LegacyRedirects', () {
    test('old chats root maps to the chats list', () {
      expect(resolve('/rooms'), '/chats');
    });

    test('sections are lifted to first-class roots', () {
      expect(resolve('/rooms/analytics'), '/analytics');
      expect(resolve('/rooms/analytics/vocab/abc'), '/analytics/vocab/abc');
      expect(resolve('/rooms/settings'), '/settings');
      expect(resolve('/rooms/settings/security'), '/settings/security');
      expect(resolve('/rooms/user_home'), '/profile');
    });

    test('settings/profile paths become menu master + page detail tokens', () {
      // world_v2 master/detail: the menu is the `settings` master; a sub-page
      // opens beside it as a `settingspage` detail (page first, menu kept).
      expect(resolve('/settings'), '/?right=settings');
      expect(resolve('/settings/learning'),
          '/?right=settingspage:learning,settings');
      expect(
        resolve('/settings/security/password'),
        '/?right=settingspage:security%2Fpassword,settings',
      );
      expect(resolve('/profile'), '/?right=settings');
      expect(resolve('/profile/edit'),
          '/?right=settingspage:profile%2Fedit,settings');
    });

    test('find/create course flows keep literal names', () {
      expect(resolve('/rooms/course'), '/courses');
      expect(resolve('/rooms/course/private'), '/courses/private');
      expect(resolve('/rooms/course/own'), '/courses/own');
      expect(
        resolve('/rooms/course/own/plan-1/invite'),
        '/courses/own/plan-1/invite',
      );
    });

    test('public course preview gets a literal prefix', () {
      expect(
        resolve('/rooms/course/!abc:server.org'),
        '/courses/preview/${Uri.encodeComponent('!abc:server.org')}',
      );
    });

    test('course spaces move under /courses', () {
      final id = Uri.encodeComponent('!s:server.org');
      expect(resolve('/rooms/spaces/!s:server.org'), '/courses/$id');
      expect(
        resolve('/rooms/spaces/!s:server.org/details'),
        '/courses/$id/details',
      );
    });

    test('retired nested activity route maps to the in-course overlay', () {
      final id = Uri.encodeComponent('!s:server.org');
      // The space id stays in the path so the activity opens in its course
      // even for a user who has not yet joined it.
      expect(
        resolve('/rooms/spaces/!s:server.org/activity/aaa'),
        '/courses/$id?activity=aaa',
      );
      final room = Uri.encodeQueryComponent('!r:x');
      expect(
        resolve('/rooms/spaces/!s:server.org/activity/aaa?roomid=!r:x'),
        '/courses/$id?activity=aaa&roomid=$room',
      );
    });

    test('encoded segments survive the rewrite', () {
      // e.g. analytics constructs with encoded slashes.
      expect(
        resolve('/rooms/analytics/vocab/comer%2FVERB'),
        '/analytics/vocab/comer%2FVERB',
      );
    });

    test('query strings survive the rewrite', () {
      final id = Uri.encodeComponent('!s:x');
      expect(
        resolve('/rooms/spaces/!s:x/activity/a?launch=true'),
        '/courses/$id?activity=a&launch=true',
      );
      expect(
        resolve('/rooms/spaces/!s:x/details?tab=course'),
        '/courses/$id/details?tab=course',
      );
    });

    test('section roots become token-driven', () {
      // chats collapses to the world path `/` with its left token — the legacy
      // `/chats` path is dropped (section identity rides in the token).
      expect(resolve('/chats'), '/?left=chats');
      expect(resolve('/chats?left=chats'), '/?left=chats'); // path still collapses
      expect(resolve('/?left=chats'), isNull); // already token-driven at /
      // the bare `/courses` add-course hub → a bare `addcourse` token at `/`.
      expect(resolve('/courses'), '/?left=addcourse');
      expect(resolve('/?left=addcourse'), isNull);
      // world_v2: a course is a ?m= map filter + a left course panel, NOT a
      // path. The bare course path (with or without an existing course token)
      // maps off the path to the filter + panel form.
      expect(resolve('/courses/!s'), '/?m=course:!s&left=course');
      expect(resolve('/courses/!s?left=course'), '/?m=course:!s&left=course');
      // the add-course wizard's first step becomes the addcourse token,
      // preserving the flow's query; deeper steps stay route-driven.
      expect(resolve('/courses/own'), '/?left=addcourse:own');
      expect(
        resolve('/courses/own?showAll=true'),
        '/?left=addcourse:own&showAll=true',
      );
      expect(resolve('/courses/browse'), '/?left=addcourse:browse');
      expect(resolve('/courses/private'), '/?left=addcourse:private');
      expect(resolve('/courses/own/plan-1'), isNull); // deeper step stays
      // analytics collapses to its right-column summary token, level included.
      expect(resolve('/analytics'), '/?right=analytics:vocab');
      expect(resolve('/analytics/morph'), '/?right=analytics:grammar');
      expect(resolve('/analytics/activities'), '/?right=analytics:sessions');
      expect(resolve('/analytics/level'), '/?right=analytics:level');
    });

    test('a course is a ?m= map filter + panels, not a path', () {
      // A room inside a course rides as a left `room` token beside the course
      // panel; the course stays the map filter.
      expect(
        resolve('/courses/!s/!room'),
        '/?m=course:!s&left=course,room:!room',
      );
      // The in-course activity overlay: the path collapses to the filter, the
      // ?activity= (and any other) query is preserved.
      expect(
        resolve('/courses/!s?activity=a'),
        '/?m=course:!s&left=course&activity=a',
      );
      // An open right column carries through the rewrite untouched.
      expect(
        resolve('/courses/!s?right=analytics:vocab'),
        '/?m=course:!s&left=course&right=analytics:vocab',
      );
      // Deep course-management pages are FLAT pushes on the course token; the
      // legacy /details shim is stripped (bare → the card, /details/<page> →
      // the page). The Completer-carrying add-a-plan flow stays route-driven.
      expect(resolve('/courses/!s/details'), '/?m=course:!s&left=course');
      expect(resolve('/courses/!s/edit'), '/?m=course:!s&left=course:edit');
      expect(resolve('/courses/!s/invite'), '/?m=course:!s&left=course:invite');
      expect(
          resolve('/courses/!s/details/edit'), '/?m=course:!s&left=course:edit');
      expect(resolve('/courses/!s/addcourse'),
          '/?m=course:!s&left=course:addcourse');
      expect(resolve('/courses/!s/addcourse/plan-1'), isNull); // route-driven
      // The /rooms/spaces chain reaches the same form in two hops (router
      // re-runs the redirect): first to /courses/…, then to the filter form.
      expect(resolve('/rooms/spaces/!s/!room'), '/courses/!s/!room');
      expect(
        resolve(resolve('/rooms/spaces/!s/!room')!),
        '/?m=course:!s&left=course,room:!room',
      );
    });

    test('a bare room and its sub-pages become a room token over the map', () {
      // world_v2: no `/rooms/:roomid` render route — it rewrites to a `room`
      // token. The sub-page tail rides the token param; query survives.
      expect(resolve('/rooms/!room:server.org'),
          '/?left=room:!room%3Aserver.org');
      expect(resolve('/rooms/!abc'), '/?left=room:!abc');
      expect(resolve('/rooms/!abc/search'), '/?left=room:!abc%2Fsearch');
      expect(resolve('/rooms/!abc/details'), '/?left=room:!abc%2Fdetails');
      expect(
        resolve('/rooms/!abc/details/permissions'),
        '/?left=room:!abc%2Fdetails%2Fpermissions',
      );
      // The invite-filter and jump-to-message queries are preserved.
      expect(
        resolve('/rooms/!abc/invite?filter=knocking'),
        '/?left=room:!abc%2Finvite&filter=knocking',
      );
      expect(resolve('/rooms/!abc?event=abc'), '/?left=room:!abc&event=abc');
      // Idempotent: the token form has no `/rooms` segment, so it never re-fires.
      expect(resolve('/?left=room:!abc'), isNull);
    });

    test('a room inside a course rides as a room push beside the course', () {
      expect(
        resolve('/courses/!s/!room/search'),
        '/?m=course:!s&left=course,room:!room%2Fsearch',
      );
      expect(
        resolve('/courses/!s/!room/details/permissions'),
        '/?m=course:!s&left=course,room:!room%2Fdetails%2Fpermissions',
      );
    });

    test('fork routes stay put', () {
      // Literal fork segments don't start with `!`, so they fall through.
      expect(resolve('/rooms/archive'), isNull);
      expect(resolve('/rooms/newprivatechat'), isNull);
      expect(resolve('/home/login'), isNull);
      expect(resolve('/'), isNull);
    });

    test('handle() never redirects to the current location', () {
      expect(LegacyRedirects.handle(Uri.parse('/')), isNull);
    });
  });
}
