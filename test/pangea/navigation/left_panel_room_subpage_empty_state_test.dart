import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_room_subpage.dart';
import 'package:fluffychat/routes/world/panel_header.dart';

void main() {
  testWidgets(
    'empty "no longer participating" state renders the panel close control (#7746)',
    (tester) async {
      // A null param drops LeftPanelRoomSubpage to its empty state before it
      // ever touches Matrix.of — the same state reached when the room is left,
      // is a space, or is unknown. Before #7746 that state was bare centered
      // text with no way to dismiss the panel.
      const closeKey = Key('the-close-button');

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(
            body: LeftPanelRoomSubpage(
              param: null,
              shareItems: null,
              closeButton: IconButton(
                key: closeKey,
                icon: Icon(Icons.close),
                onPressed: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Read the localized string from the live element tree rather than
      // awaiting L10n.delegate.load — awaiting that future stalls the
      // testWidgets fake-async clock.
      final l10n = L10n.of(tester.element(find.byType(LeftPanelRoomSubpage)));
      expect(
        find.text(l10n.youAreNoLongerParticipatingInThisChat),
        findsOneWidget,
      );
      // The empty state now carries the panel header + the injected close
      // control, so the user can dismiss it back to the map.
      expect(find.byType(PanelHeader), findsOneWidget);
      expect(find.byKey(closeKey), findsOneWidget);
    },
  );
}
