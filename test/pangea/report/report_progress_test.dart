import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/utils/report_message.dart';

/// The progress dialog shown while a report is being recorded.
///
/// Its result must be the request's, never the dialog's: if Back could dismiss
/// it, a still-pending report would read as a failure, the retry prompt would
/// open, and the late completion would pop that prompt instead.
void main() {
  late BuildContext appContext;

  Widget app() => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Builder(
      builder: (context) {
        appContext = context;
        return const Scaffold(body: Text('chat'));
      },
    ),
  );

  testWidgets('Back does not dismiss it while the report is pending', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final pending = Completer<bool>();
    final result = showReportProgress(appContext, pending.future);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(await result, isTrue);
  });

  testWidgets('a failure is the request\'s failure', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final pending = Completer<bool>();
    final result = showReportProgress(appContext, pending.future);
    await tester.pump();

    pending.complete(false);
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('chat'), findsOneWidget);
  });

  testWidgets('settling removes only its own route', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final pending = Completer<bool>();
    final result = showReportProgress(appContext, pending.future);
    await tester.pump();

    unawaited(
      showDialog<void>(
        context: appContext,
        builder: (_) => const AlertDialog(content: Text('on top')),
      ),
    );
    // Not pumpAndSettle: the spinner underneath never settles.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('on top'), findsOneWidget);

    pending.complete(true);
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(find.text('on top'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('chat'), findsOneWidget);
  });
}
