import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/routes/world/world_view_items.dart';
import 'package:fluffychat/routes/world/world_view_markers.dart';

WorldShip _ship(String id, String city) => WorldShip(
  roomId: id,
  name: id,
  point: const LatLng(0, 0),
  cityName: city,
  cityKey: city,
  aboard: false,
);

void main() {
  test('a ship alone at its city sits centred', () {
    expect(shipSlots([_ship('a', 'x')]).single.$2, 0);
  });

  test('ships at one city fan out side by side, others unaffected', () {
    final slots = {
      for (final (ship, slot) in shipSlots([
        _ship('a', 'x'),
        _ship('b', 'y'),
        _ship('c', 'x'),
        _ship('d', 'x'),
      ]))
        ship.roomId: slot,
    };
    expect(slots, {'a': -1.0, 'b': 0.0, 'c': 0.0, 'd': 1.0});
  });
}
