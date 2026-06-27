import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_constants.dart';

void main() {
  group('glideDurationFor — scales with the zoom distance (#7239)', () {
    int ms(double a, double b) =>
        WorldMapConstants.glideDurationFor(a, b).inMilliseconds;

    test('a no-zoom move is the floor', () {
      expect(ms(5, 5), 500);
    });

    test('one zoom level adds the per-level step', () {
      expect(ms(5, 6), 610); // 500 + 1*110
    });

    test('a large move is clamped to the ceiling', () {
      expect(ms(3, 18), 1400); // 500 + 15*110 = 2150 -> clamped
    });

    test('depends only on the magnitude of the delta', () {
      expect(ms(8, 12), ms(12, 8));
    });
  });

  group('glideProgress — directional pan/zoom staggering (#7239)', () {
    test(
      'endpoints: pan and zoom are 0 at t=0 and 1 at t=1, any direction',
      () {
        for (final move in [
          [3.0, 12.0], // in
          [12.0, 3.0], // out
          [7.0, 7.0], // pure pan
        ]) {
          final at0 = WorldMapConstants.glideProgress(0, move[0], move[1]);
          final at1 = WorldMapConstants.glideProgress(1, move[0], move[1]);
          expect(at0.pan, moreOrLessEquals(0));
          expect(at0.zoom, moreOrLessEquals(0));
          expect(at1.pan, moreOrLessEquals(1));
          expect(at1.zoom, moreOrLessEquals(1));
        }
      },
    );

    test(
      'zooming IN: the pan leads the zoom (pan further along mid-glide)',
      () {
        final p = WorldMapConstants.glideProgress(0.5, 3, 12);
        expect(p.pan, greaterThan(p.zoom));
      },
    );

    test('zooming OUT: the zoom leads the pan', () {
      final p = WorldMapConstants.glideProgress(0.5, 12, 3);
      expect(p.zoom, greaterThan(p.pan));
    });

    test('a pure pan (no zoom change) moves pan and zoom together', () {
      final p = WorldMapConstants.glideProgress(0.5, 7, 7);
      expect(p.pan, moreOrLessEquals(p.zoom));
    });
  });
}
