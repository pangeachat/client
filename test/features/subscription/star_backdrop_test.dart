import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/widgets/star_backdrop.dart';
import 'package:fluffychat/features/subscription/widgets/star_characters.dart';
import 'package:fluffychat/features/subscription/widgets/star_field.dart';

/// Covers #8751: the subscription surfaces used to lay an opaque
/// `colorScheme.surface` sheet over the star art, hiding it. Removing the
/// sheet left two things for these widgets to guarantee.
///
/// **Readability.** Body text now sits directly on the art. The asset's pixels
/// top out at 64% alpha, and composited over both themes' surfaces the worst
/// pixel gives these ratios against `onSurfaceVariant`, the lightest ink the
/// surfaces put on it:
///
///   opacity 1.0 -> 1.57 (light) / 1.51 (dark)   fails
///   opacity 0.5 -> 4.23 (light) / 4.03 (dark)   fails
///   opacity 0.4 -> 4.99 (light) / 5.04 (dark)   passes WCAG AA
///
/// **One set of characters, where the surface puts them.** Painted to cover,
/// the art drops the characters wherever the viewport happens to and content
/// lands on top of them. The surfaces now draw them as their own element in
/// the scroll flow, which only works if the ambient field stops above them.
void main() {
  const surface = Size(400, 500);

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: surface.width,
            height: surface.height,
            child: child,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('paints the art below the AA contrast ceiling', (tester) async {
    await pump(tester, const StarBackdrop(child: SizedBox.expand()));

    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(StarBackdrop),
        matching: find.byType(Opacity),
      ),
    );

    expect(opacity.opacity, SubscriptionConstants.starBackgroundOpacity);
    expect(
      SubscriptionConstants.starBackgroundOpacity,
      lessThanOrEqualTo(0.4),
      reason: 'above 0.4 the worst pixel drops body text below WCAG AA',
    );
  });

  testWidgets('ambient field stops above the characters when asked', (
    tester,
  ) async {
    await pump(
      tester,
      const StarBackdrop(showCharacters: false, child: SizedBox.expand()),
    );

    // Painted into a box this much taller than the surface and clipped back to
    // it, so everything from the characters down is off screen and they cannot
    // appear twice.
    expect(
      tester.getSize(find.byType(StarField)).height,
      moreOrLessEquals(
        surface.height / SubscriptionConstants.starCharactersTop,
        epsilon: 0.5,
      ),
    );
  });

  testWidgets('ambient field is whole where the surface places nothing', (
    tester,
  ) async {
    await pump(tester, const StarBackdrop(child: SizedBox.expand()));

    expect(tester.getSize(find.byType(StarField)).height, surface.height);
  });

  testWidgets('characters are cut from the art at the documented rect', (
    tester,
  ) async {
    const width = 180.0;
    await pump(tester, const Center(child: StarCharacters(width: width)));

    // Measured off the asset: the star with the two characters sits at
    // x 1885..2330, y 1780..2240 of its 4320x2400.
    final crop = tester.widget<OverflowBox>(
      find.descendant(
        of: find.byType(StarCharacters),
        matching: find.byType(OverflowBox),
      ),
    );
    expect(
      (crop.alignment as Alignment).x,
      moreOrLessEquals(-0.0271, epsilon: 1e-4),
    );
    expect(
      (crop.alignment as Alignment).y,
      moreOrLessEquals(0.8350, epsilon: 1e-4),
    );

    final size = tester.getSize(find.byType(StarCharacters));
    expect(size.width, moreOrLessEquals(width, epsilon: 0.5));
    expect(size.height, moreOrLessEquals(width * 1.0326, epsilon: 0.5));
  });

  testWidgets('the art is decorative and reports no semantics', (tester) async {
    final handle = tester.ensureSemantics();

    await pump(
      tester,
      const StarBackdrop(
        showCharacters: false,
        child: Center(child: StarCharacters()),
      ),
    );

    expect(tester.getSemantics(find.byType(StarBackdrop)).label, isEmpty);
    expect(
      find.descendant(
        of: find.byType(StarCharacters),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );

    handle.dispose();
  });
}
