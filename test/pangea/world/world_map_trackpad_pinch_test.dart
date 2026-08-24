import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/trackpad_pinch_zoom.dart';

/// Covers #8556: on the web a trackpad pinch arrives as a [PointerScaleEvent],
/// which flutter_map does not read — so the map claims that signal itself and
/// turns it into a zoom. Without it a laptop can only zoom by the on-map +/-
/// controls.
void main() {
  group('claimTrackpadPinch (#8556)', () {
    // Where the listener sits on screen, so a reported focal point that is
    // really the GLOBAL position (the mistake that would misplace the zoom
    // anchor) cannot pass.
    const listenerOrigin = Offset(40, 20);
    const cursor = Offset(160, 120);

    double? scale;
    Offset? focalPoint;
    var pinches = 0;

    Future<TestPointer> pumpMapArea(WidgetTester tester) async {
      scale = null;
      focalPoint = null;
      pinches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Padding(
            padding: EdgeInsets.only(
              left: listenerOrigin.dx,
              top: listenerOrigin.dy,
            ),
            child: Listener(
              // The map absorbs hits on its own; a bare test child does not.
              behavior: HitTestBehavior.opaque,
              onPointerSignal: (event) =>
                  claimTrackpadPinch(event, (gestureScale, gestureFocalPoint) {
                    scale = gestureScale;
                    focalPoint = gestureFocalPoint;
                    pinches++;
                  }),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(cursor));
      return pointer;
    }

    testWidgets('a pinch reports its scale factor and the cursor position '
        'within the map', (tester) async {
      final pointer = await pumpMapArea(tester);

      await tester.sendEventToBinding(pointer.scale(1.5));

      expect(pinches, 1);
      expect(scale, 1.5);
      expect(focalPoint, cursor - listenerOrigin);
    });

    testWidgets('the scroll wheel is left to the map', (tester) async {
      final pointer = await pumpMapArea(tester);

      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));

      expect(pinches, 0);
    });
  });
}
