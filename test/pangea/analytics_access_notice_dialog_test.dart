import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics_access/analytics_access_notice_dialog.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

/// #8308 — cancelling this notice leaves the course, so the learner has to read
/// it. The dialog gives the sharing choice the emphasis (a filled button) and
/// says plainly what leaving costs, and no gesture may answer it for them.
void main() {
  late OkCancelResult? result;

  Future<void> pumpDialog(WidgetTester tester) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDialog<OkCancelResult>(
              context: context,
              barrierDismissible: false,
              builder: (context) => const AnalyticsAccessNoticeDialog(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so nothing is in the
    // tree until localizations finish loading.
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('sharing is the emphasized choice', (tester) async {
    await pumpDialog(tester);
    final l10n = L10n.of(
      tester.element(find.byType(AnalyticsAccessNoticeDialog)),
    );

    expect(find.text(l10n.analyticsAccessNoticeTitle), findsOneWidget);
    expect(find.text(l10n.analyticsAccessNoticeDesc), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, l10n.shareAnalytics),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextButton, l10n.leave),
      findsOneWidget,
      reason: 'declining leaves the course, so it says so',
    );
  });

  testWidgets('sharing grants access', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(result, OkCancelResult.ok);
  });

  testWidgets('leaving declines', (tester) async {
    await pumpDialog(tester);
    await tester.tap(
      find.widgetWithText(
        TextButton,
        L10n.of(tester.element(find.byType(AnalyticsAccessNoticeDialog))).leave,
      ),
    );
    await tester.pumpAndSettle();

    expect(result, OkCancelResult.cancel);
  });

  testWidgets('a back gesture cannot answer for the learner', (tester) async {
    await pumpDialog(tester);
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(popped, isTrue, reason: 'the app consumes the gesture');
    expect(find.byType(AnalyticsAccessNoticeDialog), findsOneWidget);
    expect(
      result,
      isNull,
      reason:
          'a dismissed dialog returns null, which the caller reads as consent',
    );
  });
}
