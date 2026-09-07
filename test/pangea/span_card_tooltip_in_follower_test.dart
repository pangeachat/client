import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_card.dart';

/// #8823 — why [SpanCard] wraps itself in `TooltipVisibility(visible: false)`.
///
/// The card is mounted in an overlay that FOLLOWS the input field, so every
/// control in it sits under a RenderFollowerLayer. A Flutter Tooltip positions
/// itself with `localToGlobal(..., ancestor:)`, and computing a paint transform
/// across a follower makes the framework assert:
///
///   The paint transform cannot be reliably computed because of
///   RenderFollowerLayer(s)
///
/// It throws on every frame the pointer rests on the control, so hovering the
/// button you are about to click paints a flashing red screen. Suppressing the
/// tooltip OVERLAY avoids the transform entirely; `tooltip:` stays on each
/// button, so the accessible name — and the a11y floor check — are unchanged.
///
/// This pins the framework behaviour rather than the card, so it survives the
/// card being restructured and fails loudly if a Flutter upgrade ever changes
/// the rule the wrapper exists for.
void main() {
  Future<void> hoverTheButton(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(IconButton)));
    await tester.pump();
    // Past the tooltip's wait duration — when it would position itself.
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> pump(
    WidgetTester tester, {
    required bool insideFollower,
    required bool suppressTooltips,
  }) async {
    final link = LayerLink();
    Widget button = Material(
      child: IconButton(
        tooltip: 'Listen first',
        icon: const Icon(Icons.headphones),
        onPressed: () {},
      ),
    );
    if (suppressTooltips) {
      button = TooltipVisibility(visible: false, child: button);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: insideFollower
              ? Stack(
                  children: [
                    CompositedTransformTarget(
                      link: link,
                      child: const SizedBox(width: 10, height: 10),
                    ),
                    CompositedTransformFollower(link: link, child: button),
                  ],
                )
              : button,
        ),
      ),
    );

    // A harness that never mounted the button would pass every "no exception"
    // assertion below while testing nothing.
    expect(find.byType(IconButton), findsOneWidget);
  }

  testWidgets('a tooltip inside a follower throws when hovered', (
    tester,
  ) async {
    await pump(tester, insideFollower: true, suppressTooltips: false);
    await hoverTheButton(tester);

    expect(
      tester.takeException().toString(),
      contains('paint transform cannot be reliably computed'),
    );
  });

  testWidgets('TooltipVisibility(visible: false) makes that hover safe', (
    tester,
  ) async {
    await pump(tester, insideFollower: true, suppressTooltips: true);
    await hoverTheButton(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the same tooltip outside a follower is fine — the follower is '
      'the cause, not the tooltip', (tester) async {
    await pump(tester, insideFollower: false, suppressTooltips: false);
    await hoverTheButton(tester);

    expect(tester.takeException(), isNull);
  });

  // TooltipVisibility does not just hide the overlay — it also drops the
  // semantics `tooltip` the Tooltip would have contributed, which is the
  // accessible name of an icon-only button. Measured here so the card's
  // explicit Semantics(label:) wrappers can never be "tidied away" as
  // redundant.
  testWidgets('suppression also drops the semantics name, which is why the '
      'card labels its controls explicitly', (tester) async {
    final handle = tester.ensureSemantics();

    await pump(tester, insideFollower: true, suppressTooltips: false);
    expect(
      tester.getSemantics(find.byType(IconButton)).tooltip,
      'Listen first',
      reason: 'a plain tooltip names the button',
    );

    await pump(tester, insideFollower: true, suppressTooltips: true);
    expect(
      tester.getSemantics(find.byType(IconButton)).tooltip,
      isEmpty,
      reason:
          'suppressed, the tooltip names nothing — hence the explicit label',
    );

    handle.dispose();
  });

  testWidgets('the card\'s own controls keep their names under suppression', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              // Exactly what SpanCard.build wraps the card in.
              child: TooltipVisibility(
                visible: false,
                child: SpanCardHeader(
                  targetId: 'wa-listen-test',
                  title: 'Spelling',
                  showListenFirst: true,
                  listenFirst: false,
                  autoIGC: true,
                  onToggleListenFirst: (_) {},
                  onToggleAutoIGC: () {},
                  onFeedback: () {},
                  onLearningSettings: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The name lands on the icon's own semantics node, which is what a screen
    // reader reads for an icon-only button.
    String nameOf(IconData icon) =>
        tester.getSemantics(find.byIcon(icon)).label;

    expect(nameOf(Icons.close), 'Close');
    expect(nameOf(Icons.headphones_outlined), 'Listen first');
    expect(nameOf(Icons.more_vert), 'More options');

    handle.dispose();
  });
}
