import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_timer_widget.dart';

void main() {
  group('PracticeTimerWidget', () {
    testWidgets('shows wall-clock elapsed from startedAt', (tester) async {
      final startedAt = DateTime.now().subtract(const Duration(seconds: 90));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PracticeTimerWidget(
              startedAt: startedAt,
              onTimeUpdate: (_) {},
              isRunning: true,
            ),
          ),
        ),
      );

      expect(find.text('01:30'), findsOneWidget);

      // Unmount to cancel the periodic ticker before the test ends.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('frozen when not running (e.g. session complete)', (
      tester,
    ) async {
      final startedAt = DateTime.now().subtract(const Duration(minutes: 10));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PracticeTimerWidget(
              startedAt: startedAt,
              frozenSeconds: 42,
              onTimeUpdate: (_) {},
              isRunning: false,
            ),
          ),
        ),
      );

      expect(find.text('00:42'), findsOneWidget);
    });

    test('formatTime pads and rolls minutes', () {
      expect(PracticeTimerWidget.formatTime(0), '00:00');
      expect(PracticeTimerWidget.formatTime(61), '01:01');
      expect(PracticeTimerWidget.formatTime(3775), '62:55');
    });
  });
}
