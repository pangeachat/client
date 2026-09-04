import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

// Read-aloud stays quiet while the learner has a message open (#8396).
// `ChatController.isSuppressed` asks the shared overlay registry rather than
// its own `selectedEvents`, so these are the facts that fix depends on:
// the toolbar registers under one app-wide key, it does so synchronously (a
// frame before any selection callback lands), and it stops reporting open once
// dismissed.
//
// Design: client/.github/instructions/message-read-aloud.instructions.md
void main() {
  // The key chat.dart's `isToolbarOpen` and the analytics example-message
  // toolbar both use. One key app-wide is what makes "a message is open"
  // answerable without a reference to whichever host opened it.
  const toolbarKey = 'message_toolbar_overlay';

  bool isMessageOpen() =>
      MatrixState.pAnyState.isOverlayOpen(overlayKey: toolbarKey);

  setUp(() => MatrixState.pAnyState.closeAllOverlays(force: true));

  testWidgets('the toolbar overlay reports open from the moment it is shown', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // The overlay's backdrop names its Dismiss control through `L10n`, whose
    // delegate loads from a deferred library: nothing is built until it lands.
    await tester.pumpAndSettle();

    expect(isMessageOpen(), isFalse);

    OverlayUtil.showOverlay(
      context: context,
      child: const SizedBox.shrink(),
      displayDetails: const CenteredOverlayDisplayDetails(
        overlayKey: toolbarKey,
      ),
    );

    // Synchronously, without pumping: the overlay's own state (and the chat
    // selection it drives) only lands a frame later, and a message arriving in
    // that gap must not be read over the message being opened.
    expect(isMessageOpen(), isTrue);

    await tester.pump();
    expect(isMessageOpen(), isTrue);

    MatrixState.pAnyState.closeOverlay(toolbarKey);
    await tester.pump();
    expect(isMessageOpen(), isFalse);
  });
}
