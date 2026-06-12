import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/navigation/legacy_redirects.dart';

void main() {
  String? resolve(String location) =>
      LegacyRedirects.resolve(Uri.parse(location));

  group('LegacyRedirects', () {
    test('old chats root maps to world home', () {
      expect(resolve('/rooms'), '/');
    });

    test('sections are lifted to first-class roots', () {
      expect(resolve('/rooms/analytics'), '/analytics');
      expect(resolve('/rooms/analytics/vocab/abc'), '/analytics/vocab/abc');
      expect(resolve('/rooms/settings'), '/settings');
      expect(resolve('/rooms/settings/security'), '/settings/security');
      expect(resolve('/rooms/user_home'), '/profile');
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
        resolve('/rooms/spaces/!s:server.org/activity/aaa'),
        '/courses/$id/activity/aaa',
      );
      expect(
        resolve('/rooms/spaces/!s:server.org/details'),
        '/courses/$id/details',
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
        '/courses/$id/activity/a?launch=true',
      );
      expect(
        resolve('/rooms/spaces/!s:x/details?tab=course'),
        '/courses/$id/details?tab=course',
      );
    });

    test('matrix rooms and fork routes stay put', () {
      expect(resolve('/rooms/!room:server.org'), isNull);
      expect(resolve('/rooms/archive'), isNull);
      expect(resolve('/rooms/newgroup'), isNull);
      expect(resolve('/home/login'), isNull);
      expect(resolve('/'), isNull);
      expect(resolve('/analytics'), isNull);
    });

    test('handle() never redirects to the current location', () {
      expect(LegacyRedirects.handle(Uri.parse('/analytics')), isNull);
    });
  });
}
