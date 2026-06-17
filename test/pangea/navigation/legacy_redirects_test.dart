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

    test('settings/profile paths become the right-column settings token', () {
      // world_v2: the settings/profile tree is a right-column panel, so a
      // direct /settings or /profile location is rewritten to its token.
      expect(resolve('/settings'), '/?right=settings');
      expect(resolve('/settings/learning'), '/?right=settings:learning');
      expect(
        resolve('/settings/security/password'),
        '/?right=settings:security%2Fpassword',
      );
      expect(resolve('/profile'), '/?right=settings');
      expect(resolve('/profile/edit'), '/?right=settings:profile%2Fedit');
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
      // chats and a course keep their path and gain their left token.
      expect(resolve('/chats'), '/chats?left=chats');
      expect(resolve('/chats?left=chats'), isNull); // already token-driven
      expect(resolve('/courses/!s'), '/courses/!s?left=course');
      expect(resolve('/courses/!s?left=course'), isNull);
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

    test('matrix rooms and fork routes stay put', () {
      expect(resolve('/rooms/!room:server.org'), isNull);
      expect(resolve('/rooms/archive'), isNull);
      expect(resolve('/home/login'), isNull);
      expect(resolve('/'), isNull);
    });

    test('handle() never redirects to the current location', () {
      expect(LegacyRedirects.handle(Uri.parse('/')), isNull);
    });
  });
}
