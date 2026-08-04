import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_rating_meter.dart';

/// Render contract of the activity header's rating indicator (#8088): the
/// aggregate reads as a thumbs-up share — a thumb icon plus the percentage —
/// never a ring, so an all-negative activity shows "0%" rather than an empty
/// progress dial. An unrated activity still shows the NEW pill instead.
void main() {
  Future<void> pumpMeter(
    WidgetTester tester, {
    double? average,
    int? count,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ActivityRatingMeter(average: average, count: count),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('all-negative reads as a thumbs up at 0%', (tester) async {
    await pumpMeter(tester, average: 0.0, count: 1);

    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('one down and one up reads 50%', (tester) async {
    await pumpMeter(tester, average: 0.5, count: 2);

    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('all-positive reads 100%', (tester) async {
    await pumpMeter(tester, average: 1.0, count: 3);

    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('an unrated activity shows the NEW pill, no thumb', (
    tester,
  ) async {
    await pumpMeter(tester, average: null, count: 0);

    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });
}
