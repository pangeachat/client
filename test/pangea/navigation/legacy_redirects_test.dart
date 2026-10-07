import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/legacy_redirects.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/token_params/settings_token.dart';

/// Activity and course-join inbound rewrites. Synapse email links are covered
/// by notification_email_link_test.dart; retired internal routes stay retired.
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

  group('the inbound course join link (bare short code)', () {
    test('a bare /<code> folds to the join-with-code leaf', () {
      expect(resolve('/vj3pc8b'), '/?left=addcoursepage:private.jvj3pc8b');
    });

    test('prior panels and context are dropped — this link IS the join', () {
      expect(
        resolve('/vj3pc8b?c=!s&left=chats'),
        '/?left=addcoursepage:private.jvj3pc8b',
      );
    });

    test('a seven-char segment with no digit is not a code — left alone', () {
      expect(resolve('/abcdefg'), isNull);
    });

    test('idempotent: the token form never re-fires', () {
      expect(resolve(resolve('/vj3pc8b')!), isNull);
    });
  });

  group('the gift link /gift/<code> (subscriptions § Gift link)', () {
    const code = 'TESOL26-alice_2026';

    test('folds to the discount page alone, carrying the code', () {
      final out = resolve('/gift/$code');
      expect(out, PRoutes.giftLink(code));
      final outUri = Uri.parse(out!);
      // A workspace location (`/` with a query): the shape the login-bounce
      // ferry keeps, so the link survives sign-in like the course link.
      expect(outUri.path, '/');
      final right = parseOpenPanels(outUri).right;
      expect(right, hasLength(1));
      final param = right.single.param as SettingsTokenParam;
      expect(param.subpage, SettingsTokenParam.discountPage);
      expect(param.promoCode, code);
    });

    test('anything that is not a promo code is left alone', () {
      expect(resolve('/gift'), isNull);
      expect(resolve('/gift/'), isNull);
      expect(resolve('/gift/a/b'), isNull);
      expect(resolve('/gift/not%20a%20code'), isNull);
      expect(resolve('/gift/x.y'), isNull);
      expect(resolve('/Gift/$code'), isNull);
    });

    test('idempotent: the token form never re-fires', () {
      expect(resolve(resolve('/gift/$code')!), isNull);
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
        // The retired join-link spellings: the code is now the bare path.
        '/join_with_link?classcode=vj3pc8b',
        '/join?classcode=vj3pc8b',
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
        LegacyRedirects.handle(
          Uri.parse('/?left=addcoursepage:private%2Fvj3pc8b'),
        ),
        isNull,
      );
      expect(
        LegacyRedirects.handle(Uri.parse('/?left=addcoursepage:private')),
        isNull,
      );
    });
  });
}
