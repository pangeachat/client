import 'package:flutter/foundation.dart';
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

  // #9178 — a phone or tablet browser reaches the same dialog, but cannot open
  // device settings or point the keyboard at the target language.
  group('in a browser', () {
    testWidgets('iOS keeps the steps and drops the settings action', (
      tester,
    ) async {
      await pumpDialog(tester, const IOSEnableAutocorrectDialog(isWeb: true));

      expect(find.text('To add one, go to:'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('the app keeps the iOS settings action', (tester) async {
      await pumpDialog(tester, const IOSEnableAutocorrectDialog());

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('Android asks for a manual keyboard switch instead', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        const AndroidEnableAutocorrectDialog(isWeb: true),
      );

      expect(find.textContaining('Warning!'), findsOneWidget);
      expect(find.textContaining('your keyboard will switch'), findsNothing);
      expect(
        find.textContaining('add it in your keyboard settings'),
        findsOneWidget,
      );
      expect(find.textContaining('globe icon'), findsOneWidget);
      expect(find.text('Open Keyboard Settings'), findsNothing);
    });

    testWidgets('the platform comes from the browser\'s device', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpDialog(tester, const EnableAutocorrectDialog(isWeb: true));
        expect(find.byType(IOSEnableAutocorrectDialog), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
