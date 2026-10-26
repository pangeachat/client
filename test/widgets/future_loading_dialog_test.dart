// #9357 — a long wait says what is happening: futureWithStatus shows each
// status centred over a progress bar and announces it to screen readers.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// Pumps a button that opens [open], taps it, and waits out the dialog's
/// 300 ms show delay and its entrance transition, which keeps the dialog out
/// of the semantics tree while it runs.
Future<void> openDialog(
  WidgetTester tester,
  void Function(BuildContext context) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Builder(
        builder: (context) =>
            TextButton(onPressed: () => open(context), child: const Text('go')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('go'));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('shows and announces each status, then pops with the result', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final completer = Completer<String>();
    late void Function(String) setStatus;
    late Future<Result<String>> result;

    await openDialog(
      tester,
      (context) => result = showFutureLoadingDialog(
        context: context,
        futureWithStatus: (set) {
          setStatus = set;
          return completer.future;
        },
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // The first status shows at once.
    setStatus('First step…');
    await tester.pump();
    expect(find.text('First step…'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('First step…')),
      isSemantics(isLiveRegion: true),
    );

    // A later one waits until it has held for 250 ms, so one replaced sooner
    // never shows.
    setStatus('Quick step…');
    await tester.pump(const Duration(milliseconds: 200));
    setStatus('Slow step…');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('First step…'), findsOneWidget);
    expect(find.text('Quick step…'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Slow step…'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Slow step…')),
      isSemantics(isLiveRegion: true),
    );

    completer.complete('done');
    await tester.pumpAndSettle();
    expect(find.text('Slow step…'), findsNothing);
    expect((await result).asValue?.value, 'done');

    semantics.dispose();
  });

  testWidgets('a dialog without a status keeps the spinner layout', (
    tester,
  ) async {
    final completer = Completer<void>();

    await openDialog(
      tester,
      (context) => showFutureLoadingDialog(
        context: context,
        future: () => completer.future,
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    completer.complete();
    await tester.pumpAndSettle();
  });
}
