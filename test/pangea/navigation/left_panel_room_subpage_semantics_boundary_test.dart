import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

/// Pins the invariant behind the `Semantics(container: true)` wrapper around
/// [LeftPanelRoomSubpage]'s nested `Navigator` (#8459).
///
/// The nested Navigator exists so the room panel's overlays and dialogs stay
/// inside the panel. Its `MaterialPageRoute` lays down a `ModalBarrier`, and
/// `ModalBarrier` renders `BlockSemantics` — which drops the semantics of
/// everything painted BEFORE it. In the workspace shell that is the sibling
/// panel to the left, so with a chat open the entire chat list (rows and
/// search field alike) vanished from the accessibility tree, leaving the
/// search field with no DOM input to type into on Flutter web.
///
/// A semantics container is a semantic boundary, and the drop only propagates
/// past nodes that are not boundaries — so the wrapper confines the blocking
/// to the panel. This test would also catch that mechanism changing under a
/// Flutter upgrade, which is the failure mode the call site cannot see.
void main() {
  Widget harness({required bool wrapped}) {
    final navigator = Navigator(
      onGenerateRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
    );

    return MaterialApp(
      home: Stack(
        children: [
          // Stands in for the sibling panel painted before the room panel.
          Semantics(
            container: true,
            label: 'sibling-panel',
            child: const SizedBox(width: 100, height: 100),
          ),
          Positioned.fill(
            child: wrapped
                ? Semantics(container: true, child: navigator)
                : navigator,
          ),
        ],
      ),
    );
  }

  testWidgets(
    'a nested Navigator erases a sibling panel\'s semantics without the container (#8459)',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(harness(wrapped: false));
      await tester.pumpAndSettle();

      // The regression itself: the barrier's BlockSemantics propagates out of
      // the panel and takes the sibling with it.
      expect(find.bySemanticsLabel('sibling-panel'), findsNothing);

      handle.dispose();
    },
  );

  testWidgets(
    'the semantics container confines the blocking to the panel (#8459)',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(harness(wrapped: true));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('sibling-panel'), findsOneWidget);

      handle.dispose();
    },
  );
}
