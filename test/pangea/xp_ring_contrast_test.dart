import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'contrast_ratio.dart';

/// The XP ring paints outside the powerups pill, directly over map tiles, and
/// is the only encoding of the progress it shows (#8763). The track strokes
/// wider than the gold arc so the arc's adjacent color is the track, never raw
/// cartography — these are the two checks that keep that geometry honest.
void main() {
  // Dominant tile fields the ring's outer edge meets: OSM light cartography
  // and CARTO dark_all. CARTO's sparse #373737 detail linework is a known,
  // documented residual (2.68:1 — no color of any hue clears both it and the
  // gold arc; see the issue) and is deliberately not asserted here.
  const lightTiles = {
    'land': Color(0xFFF2EFE9),
    'road': Color(0xFFFFFFFF),
    'park': Color(0xFFC8FACC),
    'water': Color(0xFFAAD3DF),
  };
  const darkTiles = {
    'base': Color(0xFF121212),
    'water': Color(0xFF0E1116),
    'road': Color(0xFF242424),
  };

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'xp ring track clears $minGraphicRatio:1 in ${brightness.name}',
      (tester) async {
        late Color track;
        late Color arc;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true, brightness: brightness),
            home: Builder(
              builder: (context) {
                track = AppConfig.xpTrackByTheme(context);
                arc = AppConfig.goldByTheme(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(
          contrastRatio(arc, track),
          greaterThanOrEqualTo(minGraphicRatio),
          reason: 'progress boundary (arc vs track) in ${brightness.name}',
        );
        final tiles = brightness == Brightness.light ? lightTiles : darkTiles;
        for (final tile in tiles.entries) {
          expect(
            contrastRatio(track, tile.value),
            greaterThanOrEqualTo(minGraphicRatio),
            reason: 'track outline over ${tile.key} tile in ${brightness.name}',
          );
        }
      },
    );
  }
}
