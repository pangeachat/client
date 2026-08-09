import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/activity_detail_panel.dart';

/// Regression coverage for #7115 ("Redundant back and X buttons on activity
/// page"): the activity-resolve loading header must show exactly ONE close
/// control — a back-arrow when course-scoped, an X otherwise — never both. The
/// old header rendered ← and X together, and both did the same thing in the map/
/// pin case.
void main() {
  Future<void> pumpHeader(WidgetTester tester, {required bool showBack}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ActivityLoadingHeader(
            showBack: showBack,
            onBack: () {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('course-scoped: shows ONLY a back arrow, not an X', (
    tester,
  ) async {
    await pumpHeader(tester, showBack: true);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('pin / standalone: shows ONLY a close X, not a back arrow', (
    tester,
  ) async {
    await pumpHeader(tester, showBack: false);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('never renders both controls at once (the #7115 redundancy)', (
    tester,
  ) async {
    for (final showBack in [true, false]) {
      await pumpHeader(tester, showBack: showBack);
      final controls = find.byType(IconButton).evaluate().length;
      expect(controls, 1, reason: 'exactly one close control, never a pair');
    }
  });
}
