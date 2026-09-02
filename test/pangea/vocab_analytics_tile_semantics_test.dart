import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/vocab_analytics_list_tile.dart';

/// #8726 — a vocab tile announces its word and growth stage as ONE node.
/// Before, the no-emoji placeholder dash was a real text node (tiles read as
/// "-, lemma") and the growth stage reached assistive tech nowhere.
/// `listen: false` renders statically with no Matrix ancestor (the tile's
/// designed test knob).
void main() {
  final constructId = ConstructIdentifier(
    lemma: 'bien',
    type: ConstructTypeEnum.vocab,
    category: 'adv',
  );

  Future<void> pumpTile(
    WidgetTester tester, {
    ConstructLevelEnum level = ConstructLevelEnum.seeds,
    bool blocked = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: VocabAnalyticsListTile(
            constructId: constructId,
            level: level,
            textColor: Colors.black,
            listen: false,
            blocked: blocked,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('announces "<lemma>, <stage>" with tap, and no dash', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpTile(tester, level: ConstructLevelEnum.greens);

    final l10n = L10n.of(tester.element(find.byType(VocabAnalyticsListTile)));
    final node = tester.getSemantics(
      find.bySemanticsLabel('bien, ${l10n.constructLevelGreens}'),
    );
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'the single tile node must stay activatable',
    );
    expect(
      find.bySemanticsLabel(RegExp('^-')),
      findsNothing,
      reason: 'the placeholder dash must never reach the semantics tree',
    );
    semantics.dispose();
  });

  testWidgets('a blocked tile keeps its deleted announcement', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTile(tester, blocked: true);

    final l10n = L10n.of(tester.element(find.byType(VocabAnalyticsListTile)));
    expect(
      find.bySemanticsLabel(l10n.deletedWordLabel('bien')),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
