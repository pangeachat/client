import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_dismissals.dart';

/// Covers the #7245 dismissal TTL: an X keeps an activity out of the large
/// tier for [WorldMapDismissals.ttl], then lapses. Clock-injected — no timers.
void main() {
  final t0 = DateTime(2026, 1, 1, 12);
  DateTime plus(Duration d) => t0.add(d);

  group('WorldMapDismissals — TTL', () {
    test('a fresh dismissal is active', () {
      final d = WorldMapDismissals()..dismiss('a', t0);
      expect(d.activeIds(t0), {'a'});
    });

    test('a dismissal is active just under the TTL and lapsed at it', () {
      final d = WorldMapDismissals()..dismiss('a', t0);
      final almost = WorldMapDismissals.ttl - const Duration(seconds: 1);
      expect(d.activeIds(plus(almost)), {'a'});
      expect(d.activeIds(plus(WorldMapDismissals.ttl)), isEmpty);
    });

    test('re-dismissing restarts the clock', () {
      final d = WorldMapDismissals()..dismiss('a', t0);
      final half = WorldMapDismissals.ttl ~/ 2;
      d.dismiss('a', plus(half));
      // Past the original expiry, but within the restarted one.
      expect(d.activeIds(plus(WorldMapDismissals.ttl)), {'a'});
      expect(d.activeIds(plus(WorldMapDismissals.ttl + half)), isEmpty);
    });

    test('dismissals lapse independently', () {
      final half = WorldMapDismissals.ttl ~/ 2;
      final d = WorldMapDismissals()..dismiss('a', t0);
      d.dismiss('b', plus(half));
      expect(d.activeIds(plus(WorldMapDismissals.ttl)), {'b'});
    });
  });

  group('WorldMapDismissals — nextExpiry', () {
    test('null with nothing active', () {
      expect(WorldMapDismissals().nextExpiry(t0), isNull);
    });

    test('the earliest active dismissal sets the expiry', () {
      final d = WorldMapDismissals()..dismiss('a', t0);
      d.dismiss('b', plus(const Duration(minutes: 1)));
      expect(d.nextExpiry(t0), plus(WorldMapDismissals.ttl));
    });

    test('a lapsed dismissal no longer drives the expiry', () {
      final d = WorldMapDismissals()..dismiss('a', t0);
      final later = plus(const Duration(minutes: 1));
      d.dismiss('b', later);
      expect(
        d.nextExpiry(plus(WorldMapDismissals.ttl)),
        later.add(WorldMapDismissals.ttl),
      );
    });
  });
}
