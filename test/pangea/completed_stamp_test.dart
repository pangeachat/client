import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/completed_stamp.dart';

/// The completed stamp names itself, and counts the finishes only past one.
void main() {
  Future<void> pumpStamp(WidgetTester tester, {required int times}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(child: CompletedStamp(size: 30.0, times: times)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a single finish is named Completed and shows no count', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpStamp(tester, times: 1);

    expect(find.bySemanticsLabel('Completed'), findsOneWidget);
    expect(find.textContaining('×'), findsNothing);
    semantics.dispose();
  });

  testWidgets('repeat finishes hang a ×N badge and name the count', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpStamp(tester, times: 3);

    expect(find.bySemanticsLabel('Completed 3 times'), findsOneWidget);
    expect(find.text('×3'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the badge widens the stamp only when it shows', (tester) async {
    await pumpStamp(tester, times: 1);
    final single = tester.getSize(find.byType(CompletedStamp));
    await pumpStamp(tester, times: 2);
    final repeated = tester.getSize(find.byType(CompletedStamp));

    expect(single, const Size.square(30.0));
    expect(repeated.width, greaterThan(single.width));
  });
}
