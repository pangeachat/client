import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/widgets/layouts/workspace_shell.dart';

/// #8810 — the workspace's keyboard Tab order is its browse order: nav rail,
/// left panels, right panels, the user cluster, the map's chrome and zoom
/// controls, and the map's own stop last. The shell authors this with the
/// [WorkspaceOrder] rank on each region slot inside an ordered
/// [FocusTraversalGroup]. This pins (a) the rank table — one rank feeds both
/// the semantics sort key and the focus order, in the documented sequence —
/// and (b) the mechanism the shell relies on: ranked slots traverse by rank,
/// beating the reading-order default that made the full-screen map (rect
/// origin 0,0) the first Tab stop and the rail the last.
void main() {
  const documented = <String, WorkspaceOrder>{
    'rail': WorkspaceOrder.rail,
    'leftPanels': WorkspaceOrder.leftPanels,
    'rightPanels': WorkspaceOrder.rightPanels,
    'cluster': WorkspaceOrder.cluster,
    'mapChrome': WorkspaceOrder.mapChrome,
    'mapControls': WorkspaceOrder.mapControls,
    'map': WorkspaceOrder.map,
  };

  test('one rank per region feeds both the browse and the Tab order', () {
    double? previous;
    for (final MapEntry(key: name, value: region) in documented.entries) {
      expect(
        region.sortKey.order,
        region.focusOrder.order,
        reason: '$name: the sort key and the focus order must be one rank',
      );
      if (previous != null) {
        expect(
          region.focusOrder.order,
          greaterThan(previous),
          reason: '$name must rank after the region documented before it',
        );
      }
      previous = region.focusOrder.order;
    }
  });

  testWidgets('Tab walks the region slots by rank, not by paint or geometry', (
    tester,
  ) async {
    final nodes = {
      for (final label in documented.keys) label: FocusNode(debugLabel: label),
    };
    addTearDown(() {
      for (final n in nodes.values) {
        n.dispose();
      }
    });

    // A region slot as the shell mounts it: the rank wrapper around the
    // region, which (for the rail and the panels) is its own traversal group.
    Widget slot(String label, {bool grouped = false}) {
      Widget child = TextButton(
        focusNode: nodes[label],
        onPressed: () {},
        child: Text(label),
      );
      if (grouped) {
        child = FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: child,
        );
      }
      return FocusTraversalOrder(
        order: documented[label]!.focusOrder,
        child: child,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          // PAINT order, like the real shell: the full-screen map first (it
          // owns the 0,0 rect, so reading order would put it first), the
          // rail last.
          child: Stack(
            fit: StackFit.expand,
            children: [
              slot('map'),
              Positioned(right: 12, bottom: 28, child: slot('mapControls')),
              Positioned(
                top: 12,
                left: 400,
                width: 200,
                child: slot('mapChrome'),
              ),
              Positioned(top: 12, right: 12, child: slot('cluster')),
              Positioned(
                top: 100,
                right: 100,
                width: 200,
                child: slot('rightPanels', grouped: true),
              ),
              Positioned(
                top: 100,
                left: 100,
                width: 200,
                child: slot('leftPanels', grouped: true),
              ),
              Positioned(
                top: 300,
                left: 0,
                width: 80,
                child: slot('rail', grouped: true),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
    Future<void> tab({bool back = false}) async {
      if (back) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      if (back) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    final forward = <String?>[];
    for (var i = 0; i < documented.length; i++) {
      await tab();
      forward.add(focused());
    }
    expect(
      forward,
      documented.keys.toList(),
      reason:
          'ranked slots must traverse by rank — reading order would start '
          'at the full-screen map and end at the rail (#8810)',
    );

    // The Tab sequence is a ring: from the map, the next press is the rail.
    await tab();
    expect(
      focused(),
      'rail',
      reason: 'Tab past the last slot wraps to the rail',
    );

    // Shift+Tab walks the same ring backwards.
    final backward = <String?>[];
    for (var i = 0; i < documented.length; i++) {
      await tab(back: true);
      backward.add(focused());
    }
    expect(
      backward,
      documented.keys.toList().reversed,
      reason: 'Shift+Tab must walk the same order backwards',
    );

    // The finding's own condition: focus starts in the map (the deep-link
    // landing), and the visually-first rail must be the NEXT press — not
    // press 24 of 30 as measured on staging.
    nodes['map']!.requestFocus();
    await tester.pumpAndSettle();
    await tab();
    expect(
      focused(),
      'rail',
      reason:
          'a keyboard user starting in the map reaches the rail in one press',
    );
  });
}
