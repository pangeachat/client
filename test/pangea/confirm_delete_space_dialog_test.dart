import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/confirm_delete_space_dialog.dart';

/// #8492 — deleting a course is irreversible, so a mis-tap must not be enough:
/// the admin has to type the course code back (its name, for a course that
/// never had a code) before the delete action unlocks.
void main() {
  late bool? result;

  Future<void> pumpDialog(
    WidgetTester tester, {
    String? joinCode,
    String displayname = 'Spanish 101',
    bool hasSpaceChildren = true,
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDialog<bool>(
              context: context,
              builder: (context) => ConfirmDeleteSpaceDialog(
                joinCode: joinCode,
                displayname: displayname,
                hasSpaceChildren: hasSpaceChildren,
              ),
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

  L10n l10n(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(ConfirmDeleteSpaceDialog)));

  Finder deleteAction(WidgetTester tester) =>
      find.widgetWithText(TextButton, l10n(tester).delete);

  bool isDeleteEnabled(WidgetTester tester) =>
      tester.widget<TextButton>(deleteAction(tester)).enabled;

  Future<void> type(WidgetTester tester, String input) async {
    await tester.enterText(find.byType(TextField), input);
    await tester.pumpAndSettle();
  }

  testWidgets('prompts for the course code and starts disabled', (
    tester,
  ) async {
    await pumpDialog(tester, joinCode: 'abc1234');

    expect(find.text(l10n(tester).areYouSure), findsOneWidget);
    expect(find.text(l10n(tester).deleteSpaceDesc), findsOneWidget);
    expect(
      find.text(l10n(tester).typeCourseCodeToConfirm('abc1234')),
      findsOneWidget,
      reason: 'the admin has to be told what to type',
    );
    expect(isDeleteEnabled(tester), isFalse);
  });

  testWidgets('a wrong code leaves delete disabled', (tester) async {
    await pumpDialog(tester, joinCode: 'abc1234');
    await type(tester, 'abc1235');

    expect(isDeleteEnabled(tester), isFalse);
  });

  testWidgets('the right code enables delete and confirms', (tester) async {
    await pumpDialog(tester, joinCode: 'abc1234');
    await type(tester, 'abc1234');

    expect(isDeleteEnabled(tester), isTrue);

    await tester.tap(deleteAction(tester));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('the code matches trimmed and case-insensitively', (
    tester,
  ) async {
    await pumpDialog(tester, joinCode: 'abc1234');
    await type(tester, '  ABC1234 ');

    expect(isDeleteEnabled(tester), isTrue);
  });

  testWidgets('cancelling does not confirm', (tester) async {
    await pumpDialog(tester, joinCode: 'abc1234');
    await type(tester, 'abc1234');
    await tester.tap(find.widgetWithText(TextButton, l10n(tester).cancel));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('a course with no code confirms on its name instead', (
    tester,
  ) async {
    await pumpDialog(tester, displayname: 'Spanish 101');

    expect(
      find.text(l10n(tester).typeCourseNameToConfirm('Spanish 101')),
      findsOneWidget,
    );
    expect(isDeleteEnabled(tester), isFalse);

    await type(tester, 'spanish 101');
    expect(isDeleteEnabled(tester), isTrue);
  });

  testWidgets('an empty course says only the course is deleted', (
    tester,
  ) async {
    await pumpDialog(tester, joinCode: 'abc1234', hasSpaceChildren: false);

    expect(find.text(l10n(tester).deleteEmptySpaceDesc), findsOneWidget);
  });
}
