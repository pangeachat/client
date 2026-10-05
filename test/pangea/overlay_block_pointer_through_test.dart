import 'dart:ui' as ui show SemanticsHitTestBehavior;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/l10n/l10n.dart';
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

  /// The backdrop names its Dismiss control through `L10n`, whose delegate
  /// loads from a deferred library: settle after pumping the harness, or
  /// nothing is in the tree yet.
  Widget buildHarness({
    required bool blockPointerThrough,
    bool ignorePointer = true,
    VoidCallback? onTapBehind,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
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
                        ignorePointer: ignorePointer,
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

    await tester.pumpAndSettle();
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

    await tester.pumpAndSettle();
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

    await tester.pumpAndSettle();
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

  // #8903: a pointer-ignored overlay's backdrop still published a button node
  // over the whole screen. IgnorePointer strips its tap action, but on web the
  // engine gives any button-role node `pointer-events: all` regardless, so the
  // node swallowed the mouse events the session video's `<iframe>` needed —
  // the orchestrator's suggestion card and the star animations mount exactly
  // this backdrop. The node must declare itself transparent to native
  // hit-testing; Flutter's own hit test was already covered by IgnorePointer.
  testWidgets(
    'a pointer-ignored backdrop is transparent to native pointer hit-testing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(buildHarness(blockPointerThrough: false));

      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final backdrop = tester.getSemantics(find.bySemanticsLabel('Dismiss'));
      expect(backdrop.flagsCollection.isButton, isTrue);
      expect(
        backdrop.hitTestBehavior,
        ui.SemanticsHitTestBehavior.transparent,
        reason:
            'the web engine infers pointer-events: all from the button role '
            'even with the tap stripped by IgnorePointer, so without an '
            'explicit transparent hitTestBehavior this full-screen node blankets '
            'every DOM platform view beneath the overlay (#8903)',
      );

      semantics.dispose();
    },
  );

  testWidgets('a dismissable backdrop keeps taking pointer events', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      buildHarness(blockPointerThrough: false, ignorePointer: false),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap-to-dismiss is the backdrop's whole job: its node has to stay
    // hit-testable, or a click on the backdrop would fall through to the page.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Dismiss')).hitTestBehavior,
      ui.SemanticsHitTestBehavior.defer,
    );

    semantics.dispose();
  });
}
