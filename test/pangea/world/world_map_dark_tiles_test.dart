import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The world map's dark theme is flutter_map's dark color matrix applied over
  // OSM tiles, and the un-tiled gap color (mapBackground in
  // world_map_view.dart) is OSM's paper #F2EFE9 passed through that same
  // matrix — so gaps during zoom match the filtered tiles (#8585). If
  // flutter_map ever changes the matrix, this fails and the constant must be
  // recomputed.
  testWidgets('dark map gap color matches OSM paper through the dark filter', (
    tester,
  ) async {
    const osmPaper = Color(0xFFF2EFE9);
    const mapBackground = Color(0xFF130F0A);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        // Same ColorFiltered matrix darkModeTileBuilder applies per tile.
        child: Builder(
          builder: (context) => darkModeTilesContainerBuilder(
            context,
            Container(width: 4, height: 4, color: osmPaper),
          ),
        ),
      ),
    );

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      return image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    final r = bytes!.getUint8(0);
    final g = bytes.getUint8(1);
    final b = bytes.getUint8(2);

    expect((r - mapBackground.red).abs(), lessThanOrEqualTo(2));
    expect((g - mapBackground.green).abs(), lessThanOrEqualTo(2));
    expect((b - mapBackground.blue).abs(), lessThanOrEqualTo(2));
  });
}
