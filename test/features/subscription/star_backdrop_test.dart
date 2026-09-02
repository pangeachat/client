import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/widgets/star_backdrop.dart';

/// Covers #8751: the subscription surfaces used to lay an opaque
/// `colorScheme.surface` sheet over the star art, hiding it. The sheet is
/// gone, which leaves two things for the backdrop itself to guarantee.
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
/// **Not covering the characters.** `BoxFit.cover` scales the art to the
/// viewport height exactly on any portrait screen, which pins the star
/// carrying the two characters to 74.2%-93.3% of the body whatever the screen
/// size. Content height varies independently, so the only way the two stop
/// competing is to keep content out of that slice.
void main() {
  const bodyHeight = 500.0;

  Future<void> pump(WidgetTester tester, Widget backdrop) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, height: bodyHeight, child: backdrop),
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

  testWidgets('reserves enough height that content clears the characters', (
    tester,
  ) async {
    // The topmost the character star ever reaches under `BoxFit.cover`.
    const starTopFraction = 0.742;

    expect(
      1 - SubscriptionConstants.starBandFraction,
      lessThanOrEqualTo(starTopFraction),
      reason: 'content would reach into the star and cover the characters',
    );

    const key = Key('content');
    await pump(tester, const StarBackdrop(child: SizedBox.expand(key: key)));

    expect(
      tester.getSize(find.byKey(key)).height,
      moreOrLessEquals(
        bodyHeight * (1 - SubscriptionConstants.starBandFraction),
        epsilon: 0.5,
      ),
    );
  });

  testWidgets('gives the whole body to content when the band is waived', (
    tester,
  ) async {
    const key = Key('content');
    await pump(
      tester,
      const StarBackdrop(
        reserveStarBand: false,
        child: SizedBox.expand(key: key),
      ),
    );

    expect(tester.getSize(find.byKey(key)).height, bodyHeight);
  });

  testWidgets('is decorative and reports no semantics', (tester) async {
    final handle = tester.ensureSemantics();

    await pump(tester, const StarBackdrop(child: SizedBox.expand()));

    expect(
      find.descendant(
        of: find.byType(StarBackdrop),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    expect(tester.getSemantics(find.byType(StarBackdrop)).label, isEmpty);

    handle.dispose();
  });
}
