import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/xp_border_painter.dart';
import 'contrast_ratio.dart';

/// The XP ring paints outside the powerups pill, directly over map tiles, and
/// is the only encoding of the progress it shows (#8763). The track strokes
/// wider than the gold arc so the arc's adjacent color is the track, never raw
/// cartography — these are the two checks that keep that geometry honest.
void main() {
  // Dominant tile fields the ring's outer edge meets: Stadia's Alidade Smooth
  // and Alidade Smooth Dark (#8603), sampled from the served tiles. Sparse
  // label and border linework is deliberately not asserted here. Dark parks
  // (#383E36, about 1% of dark tiles) are left out too: every track tone that
  // clears them measures under 3:1 against the arc.
  const lightTiles = {
    'land': Color(0xFFF2F3F0),
    'road': Color(0xFFFFFFFF),
    'park': Color(0xFFDFE7DE),
    'water': Color(0xFFC1C9CC),
  };
  const darkTiles = {
    'land': Color(0xFF333333),
    'water and roads': Color(0xFF222222),
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
                track = XpBorderPainter.trackColorFor(Theme.of(context));
                arc = XpBorderPainter.arcColorFor(Theme.of(context));
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
