import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/course_context_bar.dart';
import 'package:fluffychat/routes/world/left_panel/course_card_reveal.dart';
import 'package:fluffychat/routes/world/panel_card.dart';

/// #8866 — the wide course card grows out of the context bar and shrinks back
/// into it, instead of the two snapping in place of each other. The bar and
/// the card share a header, so the animation is purely the card's height:
/// from the bar's exact height to the slot, and back before the token drops.
void main() {
  const slotHeight = 500.0;
  final fullCard = slotHeight - PanelCard.margin.vertical;

  Future<void> pump(WidgetTester tester, {required bool animateIn}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: slotHeight,
              child: CourseCardReveal(
                animateIn: animateIn,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

  /// The card's own surface — what the learner sees change height.
  double cardHeight(WidgetTester tester) => tester
      .getSize(
        find.descendant(
          of: find.byType(PanelCard),
          matching: find.byType(Material),
        ),
      )
      .height;

  CourseCardRevealState stateOf(WidgetTester tester) =>
      tester.state(find.byType(CourseCardReveal));

  testWidgets('appearing from the bar, it starts at the bar\'s height and '
      'grows to its slot', (tester) async {
    await pump(tester, animateIn: true);

    // The first frame is the bar's size — the frame the bar just left.
    expect(cardHeight(tester), CourseContextBar.height);

    await tester.pumpAndSettle();
    expect(cardHeight(tester), fullCard);
  });

  testWidgets('appearing from anywhere else, it is full-size at once', (
    tester,
  ) async {
    await pump(tester, animateIn: false);
    expect(cardHeight(tester), fullCard);
  });

  testWidgets('collapse shrinks it back to the bar\'s height, then resolves', (
    tester,
  ) async {
    await pump(tester, animateIn: false);

    final collapsed = stateOf(tester).collapse();
    // The first frame seats the ticker; the next is 100ms into the shrink.
    await tester.pump();
    // Mid-way it is between the two, so the shrink is visible, not a snap.
    await tester.pump(const Duration(milliseconds: 100));
    expect(cardHeight(tester), lessThan(fullCard));
    expect(cardHeight(tester), greaterThan(CourseContextBar.height));

    await tester.pumpAndSettle();
    expect(await collapsed, isTrue);
    expect(cardHeight(tester), CourseContextBar.height);
  });

  testWidgets('a collapse cut short resolves false, so nothing navigates', (
    tester,
  ) async {
    await pump(tester, animateIn: false);

    final collapsed = stateOf(tester).collapse();
    await tester.pump(const Duration(milliseconds: 100));
    // Torn down mid-shrink — a navigation elsewhere.
    await tester.pumpWidget(const SizedBox());

    expect(await collapsed, isFalse);
  });
}
