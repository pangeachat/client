import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/routes/world/world_map_constants.dart';

/// Covers #8859: the map tilted — and every pin with it — after a click on it
/// with Ctrl held. flutter_map's cursor/keyboard rotation is on by default and
/// is NOT gated by [InteractiveFlag.rotate]: while a Control key is the last
/// key pressed, a click on the map sets north to the cursor's angle from the
/// map centre (`setNorthOnClick`). The world map's interaction options switch
/// that off, so the camera never rotates.
void main() {
  Future<MapController> pumpMap(
    WidgetTester tester,
    InteractionOptions interactionOptions,
  ) async {
    final controller = MapController();
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          mapController: controller,
          options: MapOptions(
            initialCenter: const LatLng(0, 0),
            initialZoom: 3,
            interactionOptions: interactionOptions,
          ),
          children: const [],
        ),
      ),
    );
    return controller;
  }

  /// The #8859 gesture: a click left of the map centre with Ctrl held.
  Future<void> ctrlClick(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tapAt(
      tester.getCenter(find.byType(FlutterMap)) - const Offset(200, 0),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    // Lets the map's double-tap detection window lapse.
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
    'flutter_map rotates on a Ctrl-held click even with the rotate flag off '
    '(the #8859 mechanism)',
    (tester) async {
      final controller = await pumpMap(
        tester,
        const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      );

      await ctrlClick(tester);

      expect(controller.camera.rotation, isNot(0));
    },
  );

  testWidgets('the world map does not rotate on a Ctrl-held click', (
    tester,
  ) async {
    final focusNode = FocusNode();
    final controller = await pumpMap(
      tester,
      WorldMapConstants.interactionOptions(keyboardFocusNode: focusNode),
    );

    await ctrlClick(tester);

    expect(controller.camera.rotation, 0);
    await tester.pumpWidget(const SizedBox());
    focusNode.dispose();
  });
}
