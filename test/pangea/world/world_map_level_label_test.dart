import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_filter_bar.dart';

/// The Level pill's two label registers (#8287): the dropdown entries carry the
/// full ACTFL name beside the CEFR code (the settings-wide
/// [LanguageLevelTypeEnum.title] strings), while the pill itself keeps the
/// compact CEFR code (`✓ B1` per world-map.instructions.md).
void main() {
  Future<void> pump(WidgetTester tester, WorldMapFilter filter) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: WorldMapFilterBar(
            filter: filter,
            onSetLevel: (_) {},
            onSetPartySize: (_) {},
            onSetStatus: (_) {},
            onReset: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the level dropdown shows ACTFL names beside CEFR codes', (
    tester,
  ) async {
    await pump(tester, const WorldMapFilter());
    await tester.tap(find.text('All levels'));
    await tester.pumpAndSettle();

    expect(find.text('Novice Low (Pre A1)'), findsOneWidget);
    expect(find.text('Novice Mid (A1)'), findsOneWidget);
    expect(find.text('Superior (C2)'), findsOneWidget);
  });

  testWidgets('a selected level keeps the compact CEFR code on the pill', (
    tester,
  ) async {
    await pump(
      tester,
      const WorldMapFilter(cefrFilter: {LanguageLevelTypeEnum.b1}),
    );
    expect(find.text('B1'), findsOneWidget);
    expect(find.text('Intermediate Mid (B1)'), findsNothing);
  });
}
