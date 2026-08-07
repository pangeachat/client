import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/vocab_analytics_list_tile.dart';

/// The deleted-vocab tile (#6803). `listen: false` keeps the tile free of any
/// Matrix ancestor, so these pump in a bare MaterialApp.
void main() {
  final id = ConstructIdentifier(
    lemma: 'hablar',
    type: ConstructTypeEnum.vocab,
    category: 'verb',
  );

  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );

  bool isDimmed(WidgetTester tester) => tester
      .widgetList<Opacity>(find.byType(Opacity))
      .any((o) => o.opacity < 1.0);

  testWidgets('an unblocked tile renders undimmed', (tester) async {
    await tester.pumpWidget(
      wrap(
        VocabAnalyticsListTile(
          constructId: id,
          textColor: Colors.black,
          listen: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('hablar'), findsOneWidget);
    expect(isDimmed(tester), isFalse);
  });

  testWidgets('a blocked tile is dimmed', (tester) async {
    await tester.pumpWidget(
      wrap(
        VocabAnalyticsListTile(
          constructId: id,
          textColor: Colors.black,
          listen: false,
          blocked: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(isDimmed(tester), isTrue);
  });

  testWidgets('a blocked tile names its state and stays tappable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    var longPresses = 0;

    await tester.pumpWidget(
      wrap(
        VocabAnalyticsListTile(
          constructId: id,
          textColor: Colors.black,
          listen: false,
          blocked: true,
          onTap: () => taps++,
          onLongPress: () => longPresses++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Dimming is the only visual marker and is invisible to a screen reader, so
    // the blocked state has to be in the accessible name — and the row must
    // still be reachable as a button, which a bare ExcludeSemantics would break.
    expect(
      find.bySemanticsLabel('hablar, deleted'),
      findsOneWidget,
      reason: 'blocked state must reach the semantics tree',
    );

    await tester.tap(find.byType(VocabAnalyticsListTile));
    await tester.longPress(find.byType(VocabAnalyticsListTile));
    expect(taps, 1);
    expect(longPresses, 1);

    handle.dispose();
  });
}
