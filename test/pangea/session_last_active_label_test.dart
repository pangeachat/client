import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/session_last_active_label.dart';

/// An open session's tile says when its members were last online the way a
/// profile does (activity-start-page.instructions.md, "Open sessions").
void main() {
  Future<void> pumpLabel(WidgetTester tester, DateTime? lastActive) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: SessionLastActiveLabel(lastActive: lastActive)),
      ),
    );
    // The localizations load asynchronously.
    await tester.pumpAndSettle();
  }

  testWidgets('a member online just now reads as currently active', (
    tester,
  ) async {
    await pumpLabel(tester, DateTime.now());
    expect(find.text('Currently active'), findsOneWidget);
  });

  testWidgets('an earlier time reads as last active at that time', (
    tester,
  ) async {
    await pumpLabel(
      tester,
      DateTime.now().subtract(const Duration(minutes: 5)),
    );
    expect(find.textContaining('Last active: '), findsOneWidget);
    expect(find.text('Currently active'), findsNothing);
  });

  testWidgets('no known presence shows nothing', (tester) async {
    await pumpLabel(tester, null);
    expect(find.byType(Text), findsNothing);
  });
}
