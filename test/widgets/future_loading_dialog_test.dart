// #9357 — a long wait says what is happening: futureWithStatus replaces the
// dialog's label with each status and announces it to screen readers.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

void main() {
  testWidgets('shows and announces each status, then pops with the result', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final completer = Completer<String>();
    late void Function(String) setStatus;
    late Future<Result<String>> result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showFutureLoadingDialog(
              context: context,
              futureWithStatus: (set) {
                setStatus = set;
                return completer.future;
              },
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('go'));
    // Past the dialog's 300 ms show delay and its entrance transition, which
    // keeps the dialog out of the semantics tree while it runs.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));

    for (final status in ['First step…', 'Second step…']) {
      setStatus(status);
      await tester.pump();
      expect(find.text(status), findsOneWidget);
      expect(
        tester.getSemantics(find.text(status)),
        isSemantics(isLiveRegion: true),
      );
    }

    completer.complete('done');
    await tester.pumpAndSettle();
    expect(find.text('Second step…'), findsNothing);
    expect((await result).asValue?.value, 'done');

    semantics.dispose();
  });
}
