import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';

/// Pins #8970: every shimmer on screen pulses on one clock.
///
/// The role cards each used to own an `AnimationController` started at mount,
/// so a card that mounted late — or one whose shimmer was switched off while
/// the pointer hovered it and back on afterwards — restarted its pulse from
/// zero and flashed against the beat of its neighbours. Phase now comes from
/// elapsed time alone, so a late or resumed shimmer lands in step.
void main() {
  /// Alpha of the pulse overlay painted over the child with this [key].
  double alphaOf(WidgetTester tester, Key key) {
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: find.byKey(key), matching: find.byType(DecoratedBox)),
    );
    return ((box.decoration as BoxDecoration).color!).a;
  }

  Widget harness({required bool secondEnabled}) => MaterialApp(
    home: Row(
      children: [
        const ShimmerBackground(
          key: Key('first'),
          child: SizedBox.square(dimension: 10.0),
        ),
        ShimmerBackground(
          key: const Key('second'),
          enabled: secondEnabled,
          child: const SizedBox.square(dimension: 10.0),
        ),
      ],
    ),
  );

  testWidgets('a shimmer that resumes after a hover is back in phase', (
    tester,
  ) async {
    // The second card starts hovered, so only the first is pulsing.
    await tester.pumpWidget(harness(secondEnabled: false));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(DecoratedBox), findsOneWidget);

    // Pointer leaves, mid-pulse: the resumed card must match, not restart.
    await tester.pumpWidget(harness(secondEnabled: true));
    await tester.pump(const Duration(milliseconds: 150));

    final first = alphaOf(tester, const Key('first'));
    expect(first, greaterThan(0.0), reason: 'mid-pulse, not at rest');
    expect(alphaOf(tester, const Key('second')), first);

    // Let it run: still in step a pulse and a half later.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(
      alphaOf(tester, const Key('second')),
      alphaOf(tester, const Key('first')),
    );

    // Leave nothing ticking behind us.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('pulseProgress', () {
    const shimmer = ShimmerBackground(child: SizedBox.shrink());

    test('fades up over a pulse, back down over the next, and repeats', () {
      expect(shimmer.pulseProgress(Duration.zero), 0.0);
      expect(shimmer.pulseProgress(const Duration(milliseconds: 1000)), 1.0);
      expect(shimmer.pulseProgress(const Duration(milliseconds: 2000)), 0.0);
      expect(
        shimmer.pulseProgress(const Duration(milliseconds: 2500)),
        shimmer.pulseProgress(const Duration(milliseconds: 500)),
      );
    });

    test('holds at rest for delayBetweenPulses between pulses', () {
      const delayed = ShimmerBackground(
        delayBetweenPulses: Duration(seconds: 5),
        child: SizedBox.shrink(),
      );

      expect(delayed.pulseProgress(const Duration(milliseconds: 1000)), 1.0);
      expect(delayed.pulseProgress(const Duration(milliseconds: 4000)), 0.0);
      expect(
        delayed.pulseProgress(const Duration(milliseconds: 7500)),
        greaterThan(0.0),
      );
    });
  });
}
