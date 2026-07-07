import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/legacy_redirects.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

/// The ONE inbound URL rewrite (routing.instructions.md): the shareable
/// standalone activity link. Every other legacy shape is deleted, not
/// redirected — the client is the only producer of its URLs.
void main() {
  String? resolve(String location) =>
      LegacyRedirects.resolve(Uri.parse(location));
  const id = '32ad3c08-e501-41c5-b544-0875026090ed';

  group('the shareable /<uuid> activity link', () {
    test('rewrites to its activity token over the world map', () {
      expect(resolve('/$id'), '/?left=activity:$id');
    });

    test('link params fold into the token fields', () {
      final out = resolve('/$id?launch=true&roomid=!r&autoplay=1');
      final outUri = Uri.parse(out!);
      final info = activityInfoFor(outUri);
      expect(info?.activityId, id);
      expect(info?.launch, isTrue);
      expect(info?.roomId, '!r');
      expect(info?.autoplay, 1);
      expect(outUri.queryParameters['launch'], isNull);
      expect(outUri.queryParameters['roomid'], isNull);
      expect(outUri.queryParameters['autoplay'], isNull);
    });

    test(
      'prior panels and context are dropped — this link IS the activity',
      () {
        expect(resolve('/$id?c=!s&left=chats'), '/?left=activity:$id');
      },
    );

    test('idempotent: the token form never re-fires', () {
      expect(resolve(resolve('/$id')!), isNull);
    });
  });

  group('everything else is left alone (no legacy support)', () {
    test('retired shapes resolve to nothing — dead links by design', () {
      for (final dead in [
        '/chats',
        '/settings/security',
        '/analytics/vocab',
        '/courses/!s',
        '/courses/!s?activity=$id',
        '/rooms/!abc',
        '/rooms/!abc/details',
        '/rooms/spaces/!s/!room',
      ]) {
        expect(resolve(dead), isNull, reason: dead);
      }
    });

    test('live routes and token URLs pass through untouched', () {
      expect(resolve('/'), isNull);
      expect(resolve('/?c=!s&left=course,room:!a'), isNull);
      expect(resolve('/rooms/archive/!abc'), isNull);
      expect(resolve('/courses/own/plan-1'), isNull);
      expect(resolve('/courses/preview/!abc'), isNull);
    });
  });

  group('handle()', () {
    test('never redirects to the current location', () {
      expect(LegacyRedirects.handle(Uri.parse('/?left=chats')), isNull);
      expect(LegacyRedirects.handle(Uri.parse('/')), isNull);
    });
  });
}
