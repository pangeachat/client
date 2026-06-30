import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map.dart';

/// Covers the geometry behind #7155 — the minimal camera nudge that keeps a
/// tap-selected card on-screen. The card's footprint sits above its pin; this
/// computes the least screen translation that brings it into the uncovered area.
void main() {
  group('WorldMapController.minimalShiftToFit (#7155)', () {
    const safe = Rect.fromLTRB(0, 0, 1000, 800);

    test('no shift when the card already fits', () {
      expect(
        WorldMapController.minimalShiftToFit(
          const Rect.fromLTWH(300, 300, 260, 184),
          safe,
        ),
        Offset.zero,
      );
    });

    test('shifts left when the card overflows the right edge', () {
      // right = 760 + 260 = 1020, i.e. 20px past safe.right (1000).
      expect(
        WorldMapController.minimalShiftToFit(
          const Rect.fromLTWH(760, 300, 260, 184),
          safe,
        ),
        const Offset(-20, 0),
      );
    });

    test('shifts right when the card overflows the left edge', () {
      // left = -30, i.e. 30px short of safe.left (0).
      expect(
        WorldMapController.minimalShiftToFit(
          const Rect.fromLTWH(-30, 300, 260, 184),
          safe,
        ),
        const Offset(30, 0),
      );
    });

    test('shifts down when the card overflows the top edge', () {
      // top = -40, i.e. 40px above safe.top (0); the card sits above its pin.
      expect(
        WorldMapController.minimalShiftToFit(
          const Rect.fromLTWH(300, -40, 260, 184),
          safe,
        ),
        const Offset(0, 40),
      );
    });

    test('aligns top-left when the card is larger than the safe area', () {
      // A narrow uncovered area (panels open): the card can't fully fit, so it
      // aligns its top/left rather than zooming out — the header stays visible.
      expect(
        WorldMapController.minimalShiftToFit(
          const Rect.fromLTWH(50, 50, 260, 184),
          const Rect.fromLTRB(100, 100, 200, 200),
        ),
        const Offset(50, 50),
      );
    });
  });
}
