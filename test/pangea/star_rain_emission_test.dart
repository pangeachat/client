import 'package:flutter/material.dart';

import 'package:confetti/confetti.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/widgets/star_rain_widget.dart';

void main() {
  testWidgets('star rain still emits particles on slow frames', (tester) async {
    // The confetti package suppresses ALL emission on any frame slower than
    // 1/60s when this is left at its default. That renders an empty canvas —
    // no celebration at all — on any machine that misses 60fps (#8796).
    await tester.pumpWidget(
      const MaterialApp(home: StarRainWidget(overlayKey: 'test-star-rain')),
    );

    final emitters = tester.widgetList<ConfettiWidget>(
      find.byType(ConfettiWidget),
    );

    expect(emitters, isNotEmpty);
    for (final emitter in emitters) {
      expect(emitter.pauseEmissionOnLowFrameRate, isFalse);
    }

    // Run out the widget's own close timers so none are pending at teardown.
    await tester.pump(StarRainWidget.rainDuration);
    await tester.pump(StarRainWidget.opacityDuration);
  });
}
