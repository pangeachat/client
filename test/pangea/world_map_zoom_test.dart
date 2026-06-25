import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map.dart';

void main() {
  // The on-map +/- buttons must grey out at the camera's zoom limits so a tap
  // can never no-op (#7171). The limits are the single source shared by
  // FlutterMap's MapOptions, zoomBy's clamp, and the World reset.
  group('WorldMapController zoom limits (#7171)', () {
    test('zoom-in is enabled below max and disabled at max', () {
      expect(WorldMapController.canZoomIn(WorldMapController.minZoom), isTrue);
      expect(
        WorldMapController.canZoomIn(WorldMapController.maxZoom - 0.5),
        isTrue,
      );
      expect(WorldMapController.canZoomIn(WorldMapController.maxZoom), isFalse);
    });

    test('zoom-out is enabled above min and disabled at min', () {
      expect(WorldMapController.canZoomOut(WorldMapController.maxZoom), isTrue);
      expect(
        WorldMapController.canZoomOut(WorldMapController.minZoom + 0.5),
        isTrue,
      );
      expect(
        WorldMapController.canZoomOut(WorldMapController.minZoom),
        isFalse,
      );
    });

    test('the zoom range is non-empty (min below max)', () {
      expect(WorldMapController.minZoom, lessThan(WorldMapController.maxZoom));
    });
  });
}
