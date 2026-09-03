import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

/// Pins the semantics invariants around [LeftPanelRoomSubpage]'s nested
/// `Navigator` (#8459, #8729).
///
/// The nested Navigator exists so the room panel's overlays and dialogs stay
/// inside the panel. Its `MaterialPageRoute` lays down a `ModalBarrier`, and
/// `ModalBarrier` renders `BlockSemantics` — which drops the semantics of
/// everything painted BEFORE it. In the workspace shell that is the sibling
/// panel to the left, so with a chat open the entire chat list (rows and
/// search field alike) vanished from the accessibility tree, leaving the
/// search field with no DOM input to type into on Flutter web (#8459).
///
/// A semantics container is a semantic boundary, and the drop only propagates
/// past nodes that are not boundaries. Since #8729 that boundary is the NAMED
/// panel-group container [WorkspaceLeftPanel] wraps every panel in — the
/// subpage adds no container of its own, because an extra unlabeled one became
/// a nameless screen-reader stop directly inside the named group, describing
/// the whole chat by its children instead of announcing the panel's name.
/// These tests would also catch the boundary mechanism changing under a
/// Flutter upgrade, which is the failure mode the call sites cannot see.
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
            // The wrapped shape mirrors the dispatcher's: one NAMED group
            // (#8729) around the panel, nothing between it and the Navigator.
            child: wrapped
                ? Semantics(
                    container: true,
                    label: 'Chat page',
                    child: navigator,
                  )
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
    'the named panel group confines the blocking and keeps its name (#8459, #8729)',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(harness(wrapped: true));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('sibling-panel'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Chat page'),
        findsOneWidget,
        reason:
            'the named group is the blocking boundary — the name must '
            'survive the barrier inside it (#8729)',
      );

      handle.dispose();
    },
  );
}
