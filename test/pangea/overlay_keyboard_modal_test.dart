import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// #9191: with the message toolbar open, Tab kept walking the chat behind the
/// scrim and never reached the toolbar's own controls, and no key closed it.
/// An [OverlayEntry] sits outside the page route's focus scope, so both
/// halves of that are what an overlay does by default; `keyboardModal` is the
/// opt-in that gives it a scope of its own, an Escape, and a focus hand-back.
void main() {
  const overlayKey = 'keyboard-modal-overlay';
  final behindFocusNode = FocusNode(debugLabel: 'behind');

  /// The backdrop names its Dismiss control through `L10n`, whose delegate
  /// loads from a deferred library: settle after pumping the harness, or
  /// nothing is in the tree yet.
  Widget buildHarness({required bool keyboardModal, VoidCallback? onDismiss}) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              // Stands in for the message that opens the toolbar.
              TextButton(
                onPressed: () => OverlayUtil.showOverlay(
                  context: context,
                  child: Column(
                    children: [
                      TextButton(onPressed: () {}, child: const Text('first')),
                      TextButton(onPressed: () {}, child: const Text('second')),
                    ],
                  ),
                  displayDetails: CenteredOverlayDisplayDetails(
                    overlayKey: overlayKey,
                    keyboardModal: keyboardModal,
                    onDismiss: onDismiss,
                  ),
                ),
                child: const Text('open'),
              ),
              // Stands in for the rest of the chat behind the scrim.
              TextButton(
                focusNode: behindFocusNode,
                onPressed: () {},
                child: const Text('behind'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool isFocused(WidgetTester tester, String label) =>
      Focus.of(tester.element(find.text(label))).hasPrimaryFocus;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// Opens the overlay the way a keyboard user does: Tab to the opener, Enter.
  Future<void> openByKeyboard(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.tab);
    expect(isFocused(tester, 'open'), isTrue);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text('first'), findsOneWidget);
  }

  tearDown(() => MatrixState.pAnyState.closeAllOverlays(force: true));

  testWidgets('Tab cycles through the overlay and never reaches the page', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(keyboardModal: true));
    await openByKeyboard(tester);

    final visited = <String>[];
    for (var i = 0; i < 5; i++) {
      await press(tester, LogicalKeyboardKey.tab);
      visited.add(
        ['first', 'second', 'open', 'behind'].firstWhere(
          (label) => isFocused(tester, label),
          orElse: () => 'nothing',
        ),
      );
    }

    expect(visited, ['first', 'second', 'first', 'second', 'first']);
  });

  testWidgets('Escape dismisses the overlay and returns focus to its opener', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(
      buildHarness(keyboardModal: true, onDismiss: () => dismissed++),
    );
    await openByKeyboard(tester);
    await press(tester, LogicalKeyboardKey.tab);

    await press(tester, LogicalKeyboardKey.escape);

    expect(dismissed, 1);
    expect(find.text('first'), findsNothing);
    expect(isFocused(tester, 'open'), isTrue);
  });

  // Editing a message closes the toolbar and focuses the composer in the same
  // breath; the hand-back must not take that focus away again.
  testWidgets('a focus claim made while closing is left alone', (tester) async {
    await tester.pumpWidget(buildHarness(keyboardModal: true));
    await openByKeyboard(tester);

    MatrixState.pAnyState.closeOverlay(overlayKey);
    behindFocusNode.requestFocus();
    await tester.pumpAndSettle();

    expect(find.text('first'), findsNothing);
    expect(isFocused(tester, 'behind'), isTrue);
  });

  // The negative control, and the bug as reported: an entry that does not opt
  // in leaves Tab on the page and its own controls out of reach.
  testWidgets('an overlay that does not opt in leaves Tab on the page', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(keyboardModal: false));
    await openByKeyboard(tester);

    await press(tester, LogicalKeyboardKey.tab);
    expect(isFocused(tester, 'behind'), isTrue);

    await press(tester, LogicalKeyboardKey.escape);
    expect(find.text('first'), findsOneWidget);
  });
}
