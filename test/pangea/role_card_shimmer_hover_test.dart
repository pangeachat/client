import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_participant_indicator.dart';

/// Pins #9220: resting the pointer on a shimmering role card must not change
/// what any card on the page does.
///
/// Hover used to switch the hovered card's shimmer off, and switching one off
/// ends its run rather than pausing it — so the pointer leaving bought that
/// card a fresh pair of pulses after its neighbour had already spent its own,
/// and the learner watched one card flash alone. The two-pulse run itself is
/// #9003.
void main() {
  const a = Key('role-card-a');
  const b = Key('role-card-b');

  /// Alpha of the gold wash over the card with this [key], or null when no
  /// wash is painted. The wash is the card's only translucent fill — its own
  /// surface and its empty-seat avatar are opaque.
  double? washAlpha(WidgetTester tester, Key key) {
    final alphas = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => (box.decoration as BoxDecoration).color)
        .nonNulls
        .map((color) => color.a)
        .where((alpha) => alpha < 1.0);

    return alphas.isEmpty ? null : alphas.single;
  }

  Widget harness() => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: const Scaffold(
      body: Row(
        children: [
          Expanded(
            child: ActivityParticipantIndicator(
              key: a,
              name: 'A',
              shimmer: true,
            ),
          ),
          Expanded(
            child: ActivityParticipantIndicator(
              key: b,
              name: 'B',
              shimmer: true,
            ),
          ),
        ],
      ),
    ),
  );

  testWidgets('a hovered role card pulses in step, for one run only', (
    tester,
  ) async {
    // Quarter of a pulse, so every frame of the walk below lands somewhere
    // different in the cycle.
    const step = Duration(milliseconds: 250);
    const shimmer = ShimmerBackground(child: SizedBox.shrink());

    await tester.pumpWidget(harness());
    await tester.pump(); // The shared clock's first tick.
    await tester.pump(step);
    await tester.pump(step);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);

    // The pointer comes to rest on one card partway through the first pulse —
    // the report's gesture.
    await pointer.moveTo(tester.getCenter(find.byKey(a)));

    // Walk the rest of the run, with a couple of frames to spare at the end.
    double brightest = 0.0;
    final frames = shimmer.runDuration.inMicroseconds ~/ step.inMicroseconds;
    for (var frame = 0; frame <= frames; frame++) {
      await tester.pump(step);
      final hovered = washAlpha(tester, a);
      expect(
        hovered,
        washAlpha(tester, b),
        reason:
            'the hovered card must read the same as its neighbour on every '
            'frame — frame $frame of the run',
      );
      brightest = (hovered ?? 0.0) > brightest ? hovered! : brightest;
    }

    expect(brightest, greaterThan(0.0), reason: 'it pulsed while hovered');
    expect(washAlpha(tester, a), isNull, reason: 'the run is spent');
    expect(washAlpha(tester, b), isNull);

    // The pointer leaving is not a new reason to shimmer: the card it was on
    // has spent its run, exactly like the card it was never on.
    await pointer.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(step);
    expect(washAlpha(tester, a), isNull);
    expect(washAlpha(tester, b), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'clock idle');

    // Leave nothing ticking behind us.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
