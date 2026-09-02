import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/widgets/star_backdrop.dart';

/// Covers #8751: the subscription surfaces used to lay an opaque
/// `colorScheme.surface` sheet over the star art, hiding it. The sheet is
/// gone, so body text now sits directly on the art and the art's opacity is
/// what keeps that text readable.
///
/// The ceiling asserted here was measured against the live asset. Its pixels
/// top out at 64% alpha, and composited over both themes' surfaces the worst
/// pixel gives these contrast ratios against `onSurfaceVariant`, the lightest
/// ink the surfaces put on it:
///
///   opacity 1.0 -> 1.57 (light) / 1.51 (dark)   fails
///   opacity 0.5 -> 4.23 (light) / 4.03 (dark)   fails
///   opacity 0.4 -> 4.99 (light) / 5.04 (dark)   passes WCAG AA
///
/// Raising [SubscriptionConstants.starBackgroundOpacity] past the ceiling puts
/// unreadable body text back on the paywall, so the number is a contrast
/// budget rather than a taste setting.
void main() {
  const maxOpacityForAA = 0.4;

  testWidgets('star backdrop paints the art below the AA contrast ceiling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Stack(children: [StarBackdrop()])),
      ),
    );
    await tester.pump();

    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(StarBackdrop),
        matching: find.byType(Opacity),
      ),
    );

    expect(opacity.opacity, SubscriptionConstants.starBackgroundOpacity);
    expect(
      SubscriptionConstants.starBackgroundOpacity,
      lessThanOrEqualTo(maxOpacityForAA),
    );
  });

  testWidgets('star backdrop is decorative and reports no semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Stack(children: [StarBackdrop()])),
      ),
    );
    await tester.pump();

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
