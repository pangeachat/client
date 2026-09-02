import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_view.dart';

/// #8755 — the map's semantic container is a thin strip anchored at the far
/// right edge: VoiceOver sorts overlapping positioned siblings by horizontal
/// center (verified by live DOM mutation), so a full-bleed container always
/// read mid-sweep. The fix leans on two pieces of framework semantics
/// geometry this test pins as a canary: the strip container's own semantics
/// rect stays strip-sized (the box VO sorts by), while a child overflowing
/// it through a right-aligned OverflowBox lands at its true on-screen
/// position.
void main() {
  testWidgets('anchored strip: container rect is the strip, child rect true', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: semanticsAnchorWidth,
              child: Semantics(
                label: 'map-region',
                container: true,
                child: OverflowBox(
                  alignment: Alignment.centerRight,
                  minWidth: 800,
                  maxWidth: 800,
                  minHeight: 600,
                  maxHeight: 600,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 20,
                        top: 20,
                        width: 120,
                        height: 40,
                        child: Semantics(
                          label: 'far-left pin',
                          container: true,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final region = tester.getSemantics(find.bySemanticsLabel('map-region'));
    expect(
      region.rect.width,
      semanticsAnchorWidth,
      reason: "the container's own rect is the strip — the box VO sorts by",
    );

    // The default test surface is 800x600, so overflow at full surface size
    // puts children at their true screen coordinates.
    final pin = tester.getRect(find.bySemanticsLabel('far-left pin'));
    expect(
      pin,
      const Rect.fromLTWH(20, 20, 120, 40),
      reason: 'children overflowing the strip keep their true positions',
    );

    semantics.dispose();
  });
}
