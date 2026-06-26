import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_constants.dart';

void main() {
  // The on-map +/- buttons must grey out at the camera's zoom limits so a tap
  // can never no-op (#7171). The limits are the single source shared by
  // FlutterMap's MapOptions, zoomBy's clamp, and the World reset.
  group('WorldMapController zoom limits (#7171)', () {
    test('zoom-in is enabled below max and disabled at max', () {
      expect(WorldMapConstants.canZoomIn(WorldMapConstants.minZoom), isTrue);
      expect(
        WorldMapConstants.canZoomIn(WorldMapConstants.maxZoom - 0.5),
        isTrue,
      );
      expect(WorldMapConstants.canZoomIn(WorldMapConstants.maxZoom), isFalse);
    });

    test('zoom-out is enabled above min and disabled at min', () {
      expect(WorldMapConstants.canZoomOut(WorldMapConstants.maxZoom), isTrue);
      expect(
        WorldMapConstants.canZoomOut(WorldMapConstants.minZoom + 0.5),
        isTrue,
      );
      expect(WorldMapConstants.canZoomOut(WorldMapConstants.minZoom), isFalse);
    });

    test('the zoom range is non-empty (min below max)', () {
      expect(WorldMapConstants.minZoom, lessThan(WorldMapConstants.maxZoom));
    });
  });
}
