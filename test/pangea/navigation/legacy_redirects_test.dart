import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/legacy_redirects.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

/// The inbound URL rewrites (routing.instructions.md): the shareable
/// standalone activity link and the course join link. Every other legacy
/// shape is deleted, not redirected — the client is the only producer of its
/// URLs.
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

  group('the inbound course join link (#7524)', () {
    test('rewrites to the join-with-code leaf of the addcourse token', () {
      expect(
        resolve('/join_with_link?classcode=vj3pc8b'),
        '/?left=addcourse:private.jvj3pc8b',
      );
    });

    test('the native /join spelling folds to the same target', () {
      expect(
        resolve('/join?classcode=vj3pc8b'),
        '/?left=addcourse:private.jvj3pc8b',
      );
    });

    test('a code with unusual-but-valid characters round-trips losslessly', () {
      const code = 'AB.1-ç 8';
      final out = resolve(
        '/join_with_link?classcode=${Uri.encodeComponent(code)}',
      );
      expect(joinCodeFor(Uri.parse(out!)), code);
    });

    test('a missing or empty code degrades to the manual join page', () {
      expect(resolve('/join_with_link'), '/?left=addcourse:private');
      expect(resolve('/join_with_link?classcode='), '/?left=addcourse:private');
    });

    test('prior panels and context are dropped — this link IS the join', () {
      expect(
        resolve('/join_with_link?classcode=vj3pc8b&c=!s&left=chats'),
        '/?left=addcourse:private.jvj3pc8b',
      );
    });

    test('idempotent: the token form never re-fires', () {
      expect(resolve(resolve('/join_with_link?classcode=vj3pc8b')!), isNull);
      expect(resolve(resolve('/join_with_link')!), isNull);
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
      expect(
        LegacyRedirects.handle(Uri.parse('/?left=addcourse:private%2Fvj3pc8b')),
        isNull,
      );
      expect(
        LegacyRedirects.handle(Uri.parse('/?left=addcourse:private')),
        isNull,
      );
    });
  });
}
