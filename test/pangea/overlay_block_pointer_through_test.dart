import 'dart:ui' as ui show SemanticsHitTestBehavior;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// #8181: taps landing on the writing-assistance card fell through to the
/// message list behind it. Two hit-test paths had to be closed — Flutter's own
/// (inert card content never absorbs) and, on web with the semantics tree on,
/// the DOM one (the card publishes no tappable `flt-semantics` node, so the
/// browser hands the click to the message's node underneath).
void main() {
  const targetId = 'block-pointer-target';
  const overlayKey = 'block-pointer-overlay';
  const cardKey = ValueKey('card');

  Widget buildHarness({
    required bool blockPointerThrough,
    VoidCallback? onTapBehind,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Stack(
              children: [
                // Stands in for the message list behind the card.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTapBehind,
                  ),
                ),
                Center(
                  child: CompositedTransformTarget(
                    link: MatrixState.pAnyState.layerLinkAndKey(targetId).link,
                    child: SizedBox(
                      key: MatrixState.pAnyState.layerLinkAndKey(targetId).key,
                      width: 10,
                      height: 10,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  child: TextButton(
                    onPressed: () => OverlayUtil.showOverlay(
                      context: context,
                      // Inert content, like the card's padding and background:
                      // nothing here is hit-testable on its own.
                      child: const SizedBox(
                        key: cardKey,
                        width: 200,
                        height: 100,
                      ),
                      displayDetails: TransformOverlayDisplayDetails(
                        overlayKey: overlayKey,
                        transformTargetId: targetId,
                        ignorePointer: true,
                        blockPointerThrough: blockPointerThrough,
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  tearDown(() => MatrixState.pAnyState.closeAllOverlays(force: true));

  testWidgets('taps on the card do not reach the content behind it', (
    tester,
  ) async {
    var tapsBehind = 0;
    await tester.pumpWidget(
      buildHarness(blockPointerThrough: true, onTapBehind: () => tapsBehind++),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.byKey(cardKey)));
    await tester.pumpAndSettle();

    expect(tapsBehind, 0);
  });

  testWidgets('the card absorbs pointer events in the semantics tree', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(buildHarness(blockPointerThrough: true));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byKey(cardKey)).hitTestBehavior,
      ui.SemanticsHitTestBehavior.opaque,
    );

    semantics.dispose();
  });

  testWidgets('overlays stay click-through by default', (tester) async {
    final semantics = tester.ensureSemantics();
    var tapsBehind = 0;
    await tester.pumpWidget(
      buildHarness(blockPointerThrough: false, onTapBehind: () => tapsBehind++),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byKey(cardKey)).hitTestBehavior,
      ui.SemanticsHitTestBehavior.defer,
    );

    await tester.tapAt(tester.getCenter(find.byKey(cardKey)));
    await tester.pumpAndSettle();

    expect(tapsBehind, 1);

    semantics.dispose();
  });
}
