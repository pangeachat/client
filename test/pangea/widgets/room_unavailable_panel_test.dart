import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/room_unavailable_panel.dart';

/// The one room-gone page every room-scoped panel renders (#7746, #8322,
/// #8327). It draws its own chrome, so it must place the panel's injected
/// close control in that chrome — the learner always has a way out.
void main() {
  testWidgets('renders the message and the injected close control', (
    tester,
  ) async {
    const closeKey = Key('the-close-button');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const RoomUnavailablePanel(
          closeButton: IconButton(
            key: closeKey,
            icon: Icon(Icons.close),
            onPressed: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Read the localized string from the live element tree rather than
    // awaiting L10n.delegate.load — awaiting that future stalls the
    // testWidgets fake-async clock.
    final l10n = L10n.of(tester.element(find.byType(RoomUnavailablePanel)));
    expect(find.text(l10n.oopsSomethingWentWrong), findsOneWidget);
    expect(
      find.text(l10n.youAreNoLongerParticipatingInThisChat),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byKey(closeKey)),
      findsOneWidget,
    );
  });
}
