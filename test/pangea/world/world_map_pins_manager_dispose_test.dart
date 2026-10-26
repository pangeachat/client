import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_pins_manager.dart';

/// The pinged set is process-global — the course page's Mission circles read
/// it off the map — so a disposed map must not leave its pings behind.
void main() {
  test('disposing the pins manager clears the published pinged set', () {
    final manager = WorldMapPinsManager();
    WorldMapPinsManager.pingedActivityIds.value = {'a1', 'a2'};

    manager.dispose();

    expect(WorldMapPinsManager.pingedActivityIds.value, isEmpty);
  });
}
