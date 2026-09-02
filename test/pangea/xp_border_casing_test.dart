import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/xp_border_painter.dart';

const casing = Color(0xFF1D1B20);
const track = Color(0xFF878787);
const gold = Color(0xFFFDBF01);
const stroke = 5.0;

void main() {
  testWidgets('the casing is painted first and wider than the ring', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: CustomPaint(
            painter: XpBorderPainter(
              progress: 0.6,
              trackColor: track,
              progressColor: gold,
              casingColor: casing,
              stroke: stroke,
              radius: 22.5,
              anchor: XpBorderAnchor.leftCenter,
            ),
            size: const Size(140, 50),
          ),
        ),
      ),
    );

    // Order matters: the casing has to go down first or it covers the ring.
    // Width matters: equal width would leave nothing showing at the edge, so
    // the ring would still have no boundary against the map tile (#8763).
    expect(
      find.byType(CustomPaint).last,
      paints
        ..path(color: casing, strokeWidth: stroke + 2.0)
        ..path(color: track, strokeWidth: stroke)
        ..path(color: gold, strokeWidth: stroke),
    );
  });

  testWidgets('a finished ring still paints its casing', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: CustomPaint(
            painter: XpBorderPainter(
              progress: 0,
              trackColor: track,
              progressColor: gold,
              casingColor: casing,
              stroke: stroke,
              radius: 22.5,
            ),
            size: const Size(60, 140),
          ),
        ),
      ),
    );
    // progress 0 returns early after the track; the casing must already be
    // down by then, or an empty ring is invisible over pale tiles.
    expect(
      find.byType(CustomPaint).last,
      paints
        ..path(color: casing, strokeWidth: stroke + 2.0)
        ..path(color: track, strokeWidth: stroke),
    );
  });
}
