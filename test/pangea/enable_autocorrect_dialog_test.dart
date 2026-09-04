import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/enable_autocorrect_dialog.dart';

// #8804 — the dialog is shared by the autocorrect settings toggle and the
// composer's "Add keyboard" prompt. The toggle keeps each platform's default
// title; the prompt passes its own, since a learner who tapped "Add
// keyboard" is not helped by a warning that one is required.
void main() {
  const addKeyboardTitle = 'Add your target language keyboard';

  Future<void> pumpDialog(WidgetTester tester, Widget dialog) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: dialog,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('iOS', () {
    testWidgets('defaults to the autocorrect warning', (tester) async {
      await pumpDialog(tester, const IOSEnableAutocorrectDialog());

      expect(
        find.text('Warning! Requires adding your target language keyboard'),
        findsOneWidget,
      );
      // The path intro no longer repeats the title, whichever title shows.
      expect(find.text('To add one, go to:'), findsOneWidget);
    });

    testWidgets('a passed title replaces the warning', (tester) async {
      await pumpDialog(
        tester,
        const IOSEnableAutocorrectDialog(title: addKeyboardTitle),
      );

      expect(find.text(addKeyboardTitle), findsOneWidget);
      expect(find.textContaining('Warning!'), findsNothing);
      expect(find.text('To add one, go to:'), findsOneWidget);
    });
  });

  group('Android', () {
    testWidgets('defaults to the autocorrect title', (tester) async {
      await pumpDialog(tester, const AndroidEnableAutocorrectDialog());

      expect(find.text('Autocorrect in your target language'), findsOneWidget);
    });

    testWidgets('a passed title replaces the default', (tester) async {
      await pumpDialog(
        tester,
        const AndroidEnableAutocorrectDialog(title: addKeyboardTitle),
      );

      expect(find.text(addKeyboardTitle), findsOneWidget);
      expect(find.text('Autocorrect in your target language'), findsNothing);
    });
  });
}
