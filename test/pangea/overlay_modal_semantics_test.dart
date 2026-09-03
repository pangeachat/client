import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// #8783: with a message selected, the chat stayed in the accessibility tree
/// under the toolbar overlay, so a screen reader's cursor never left it. An
/// overlay opened with [OverlayDisplayDetails.modalSemanticsLabel] publishes
/// what a `ModalRoute` does: the semantics of everything painted behind it in
/// its panel are blocked (confined by the panel's named group, #8459), its
/// backdrop is a named dismiss control, and its content is a named route
/// scope — the flags assistive tech reads as "a dialog opened, move in".
///
/// Assertions read the live semantics tree: a render object dropped by
/// BlockSemantics keeps a stale cached node, which label finders still match.
void main() {
  const overlayKey = 'modal-semantics-overlay';
  const modalLabel = 'Reading assistance';
  final dismissLabel =
      const DefaultMaterialLocalizations().modalBarrierDismissLabel;

  Widget harness({required String? modalSemanticsLabel}) {
    return MaterialApp(
      home: Stack(
        children: [
          // Stands in for the sibling panel painted before the chat panel.
          Semantics(
            container: true,
            label: 'sibling-panel',
            child: const SizedBox(width: 100, height: 100),
          ),
          Positioned.fill(
            // The chat panel's shape: one NAMED group (#8729) around the
            // nested Navigator whose Overlay hosts the toolbar.
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Chat page',
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Column(
                    children: [
                      const Text('behind the overlay'),
                      TextButton(
                        onPressed: () => OverlayUtil.showOverlay(
                          context: context,
                          child: const Text('overlay content'),
                          displayDetails: CenteredOverlayDisplayDetails(
                            overlayKey: overlayKey,
                            modalSemanticsLabel: modalSemanticsLabel,
                          ),
                        ),
                        child: const Text('open'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Every node in the live tree, keyed by label (empty labels dropped).
  Map<String, SemanticsNode> nodesByLabel(WidgetTester tester) {
    SemanticsNode root = tester.getSemantics(find.byType(MaterialApp));
    while (root.parent != null) {
      root = root.parent!;
    }

    final nodes = <String, SemanticsNode>{};
    void visit(SemanticsNode node) {
      if (node.label.isNotEmpty) nodes[node.label] = node;
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(root);
    return nodes;
  }

  Future<Map<String, SemanticsNode>> openOverlay(
    WidgetTester tester, {
    required String? modalSemanticsLabel,
  }) async {
    await tester.pumpWidget(harness(modalSemanticsLabel: modalSemanticsLabel));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return nodesByLabel(tester);
  }

  tearDown(() => MatrixState.pAnyState.closeAllOverlays(force: true));

  testWidgets(
    'a modal overlay is the only content of its panel to assistive tech',
    (tester) async {
      final handle = tester.ensureSemantics();
      final nodes = await openOverlay(tester, modalSemanticsLabel: modalLabel);

      expect(
        nodes.keys,
        isNot(contains('behind the overlay')),
        reason: 'the chat behind the overlay must leave the semantics tree',
      );
      expect(nodes.keys, isNot(contains('open')));
      expect(nodes.keys, contains('overlay content'));

      // The blocking stops at the panel's named group (#8459): the panel
      // keeps its name and the sibling panel keeps its content.
      expect(nodes.keys, contains('Chat page'));
      expect(nodes.keys, contains('sibling-panel'));

      handle.dispose();
    },
  );

  testWidgets(
    'a modal overlay is a named dialog whose first stop dismisses it',
    (tester) async {
      final handle = tester.ensureSemantics();
      final nodes = await openOverlay(tester, modalSemanticsLabel: modalLabel);

      final dialog = nodes[modalLabel]!;
      expect(
        dialog,
        isSemantics(label: modalLabel, scopesRoute: true, namesRoute: true),
      );
      expect(dialog.role, SemanticsRole.dialog);

      final dismiss = nodes[dismissLabel]!;
      expect(
        dismiss,
        isSemantics(
          label: dismissLabel,
          hasTapAction: true,
          hasDismissAction: true,
        ),
      );
      // The dismiss control is the dialog's first stop: it is what a screen
      // reader lands on when the overlay opens, and its way back out.
      expect(
        dialog
            .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
            .first,
        same(dismiss),
      );

      handle.dispose();
    },
  );

  testWidgets('overlays leave the content behind them browsable by default', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final nodes = await openOverlay(tester, modalSemanticsLabel: null);

    expect(nodes.keys, contains('behind the overlay'));
    expect(nodes.keys, contains('open'));
    expect(nodes.keys, contains('overlay content'));
    expect(nodes.keys, isNot(contains(dismissLabel)));
    expect(nodes.keys, isNot(contains(modalLabel)));

    handle.dispose();
  });
}
