import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';

/// Pins #9003: a shimmer pulses [ShimmerBackground.pulsesPerRun] times each
/// time it turns on, then stops.
///
/// It used to pulse until the learner acted on it. Motion that starts on its
/// own and lasts more than five seconds needs a pause control under WCAG
/// 2.2.2, and none of the shimmers had one.
void main() {
  Widget harness({required bool enabled}) => MaterialApp(
    home: Center(
      child: ShimmerBackground(
        enabled: enabled,
        child: const SizedBox.square(dimension: 10.0),
      ),
    ),
  );

  final overlay = find.byType(DecoratedBox);

  double alpha(WidgetTester tester) =>
      (tester.widget<DecoratedBox>(overlay).decoration as BoxDecoration)
          .color!
          .a;

  test('a run ends inside the five seconds WCAG 2.2.2 allows', () {
    const shimmer = ShimmerBackground(child: SizedBox.shrink());
    expect(shimmer.runDuration, lessThan(const Duration(seconds: 5)));
  });

  testWidgets('stops after its pulses and stays stopped while on', (
    tester,
  ) async {
    await tester.pumpWidget(harness(enabled: true));
    await tester.pump(); // The clock's first tick.

    await tester.pump(const Duration(milliseconds: 1000));
    expect(alpha(tester), greaterThan(0.0), reason: 'top of the first pulse');

    await tester.pump(const Duration(milliseconds: 2900));
    expect(overlay, findsOneWidget, reason: 'second pulse still fading out');

    await tester.pump(const Duration(milliseconds: 200));
    expect(overlay, findsNothing);

    await tester.pump(const Duration(seconds: 10));
    expect(overlay, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'clock idle');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('turning back on starts a fresh run', (tester) async {
    await tester.pumpWidget(harness(enabled: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(overlay, findsNothing);

    await tester.pumpWidget(harness(enabled: false));
    await tester.pumpWidget(harness(enabled: true));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 1000));
    expect(alpha(tester), greaterThan(0.0));

    // A full run again — not cut short or stretched by the last run's time.
    await tester.pump(const Duration(milliseconds: 2900));
    expect(overlay, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(overlay, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
