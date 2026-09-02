import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;

import 'package:flutter_test/flutter_test.dart';

/// #8755 — the workspace's browse order is reading order, not paint order:
/// nav rail, left panels, right panels, the user cluster, the map last. The
/// shell authors this with `OrdinalSortKey`s on its region mounts. This pins
/// the mechanism those annotations rely on: keyed siblings traverse by key,
/// beating the default geometric sort that made the full-screen map (rect
/// origin 0,0) read first.
void main() {
  testWidgets('ordinal sort keys beat geometric order for the map backdrop', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: [
            // Paints first and owns the full-screen 0,0 rect — geometrically
            // it would traverse first, like the real map did.
            Semantics(
              sortKey: const OrdinalSortKey(5),
              child: Semantics(
                label: 'map',
                container: true,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              top: 200,
              right: 8,
              width: 100,
              height: 40,
              child: Semantics(
                sortKey: const OrdinalSortKey(3),
                child: Semantics(
                  label: 'right-panel',
                  container: true,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              width: 100,
              height: 40,
              child: Semantics(
                sortKey: const OrdinalSortKey(4),
                child: Semantics(
                  label: 'cluster',
                  container: true,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned(
              top: 200,
              left: 100,
              width: 100,
              height: 40,
              child: Semantics(
                sortKey: const OrdinalSortKey(2),
                child: Semantics(
                  label: 'left-panel',
                  container: true,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned(
              top: 300,
              left: 0,
              width: 40,
              height: 200,
              child: Semantics(
                sortKey: const OrdinalSortKey(1),
                child: Semantics(
                  label: 'rail',
                  container: true,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final regions = <String>[];
    void walk(SemanticsNode node) {
      for (final child in node.debugListChildrenInOrder(
        DebugSemanticsDumpOrder.traversalOrder,
      )) {
        final label = child.getSemanticsData().label;
        if (label.isNotEmpty) regions.add(label);
        walk(child);
      }
    }

    // ignore: deprecated_member_use
    walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);

    expect(
      regions,
      ['rail', 'left-panel', 'right-panel', 'cluster', 'map'],
      reason:
          'keyed regions must traverse by ordinal, not geometry — the '
          "full-screen backdrop's 0,0 rect otherwise reads first (#8755)",
    );
    semantics.dispose();
  });
}
