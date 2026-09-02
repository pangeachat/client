import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_view.dart';
import 'package:fluffychat/widgets/layouts/workspace_shell.dart';

/// #8755 — the map's semantic container is a thin strip anchored at the far
/// right edge: VoiceOver sorts overlapping positioned siblings by horizontal
/// center (verified by live DOM mutation), so a full-bleed container always
/// read mid-sweep. [MapSemanticsAnchor] carries three contracts this pins:
/// the group node's own rect stays strip-sized (the box VO sorts by),
/// children keep their true on-screen positions, and clickable children
/// beyond the strip's bounds still receive pointer hits — the part a chain
/// of framework proxies (Semantics + OverflowBox) cannot deliver.
void main() {
  testWidgets('anchor: strip-sized group, true child rects, live pointers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: semanticsAnchorWidth,
              child: MapSemanticsAnchor(
                label: 'map-region',
                sortKey: BrowseOrder.map,
                // The default test surface size, so full-size overflow puts
                // children at their true screen coordinates.
                fullSize: const Size(800, 600),
                child: Stack(
                  children: [
                    Positioned(
                      left: 20,
                      top: 20,
                      width: 120,
                      height: 40,
                      child: TextButton(
                        onPressed: () => tapped = true,
                        child: const Text('far-left control'),
                      ),
                    ),
                  ],
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
      reason: "the group's own rect is the strip — the box VO sorts by",
    );

    expect(
      tester.getRect(find.byType(TextButton)),
      const Rect.fromLTWH(20, 20, 120, 40),
      reason: 'children overflowing the strip keep their true positions',
    );

    await tester.tapAt(const Offset(80, 40));
    await tester.pumpAndSettle();
    expect(
      tapped,
      isTrue,
      reason:
          'clickable children beyond the strip bounds must still receive '
          'pointer hits (#8755 — the zoom controls live inside the group)',
    );

    semantics.dispose();
  });
}
