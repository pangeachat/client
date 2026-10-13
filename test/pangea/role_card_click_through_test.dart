import 'dart:ui' as ui show SemanticsHitTestBehavior;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_participant_indicator.dart';

/// #9287: once a role is chosen, a click on an open seat's card fell through
/// to the start page's play-video poster behind it. On web with the semantics
/// tree on the browser dispatches clicks by the `flt-semantics` DOM, and a
/// card with no tap action published no node of its own to take them. A
/// widget test has no DOM, so this pins the property that fixes it.
void main() {
  const openSeat = Key('open-seat');
  const tappable = Key('tappable');

  testWidgets('every role card takes the clicks that land on it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(
                child: ActivityParticipantIndicator(
                  key: openSeat,
                  name: 'Open',
                  selectable: false,
                ),
              ),
              Expanded(
                child: ActivityParticipantIndicator(
                  key: tappable,
                  name: 'Tappable',
                  onTap: () => taps++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final card in [openSeat, tappable]) {
      expect(
        tester.getSemantics(find.byKey(card)).hitTestBehavior,
        ui.SemanticsHitTestBehavior.opaque,
        reason: '$card',
      );
    }

    await tester.tap(find.byKey(tappable));
    expect(taps, 1);

    semantics.dispose();
  });
}
