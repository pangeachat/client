import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';

/// The XP a use is worth is drawn in the theme's gold, not a hard-coded hex
/// (#8491). The Level panel's own gold marks — the level shield, the XP ring
/// the panel opens from — all read [AppConfig.goldByTheme], which resolves to
/// the theme's [PangeaColors.goldFixedDim] in both brightnesses.
void main() {
  OneConstructUse use(int xp) => OneConstructUse(
    useType: ConstructUseTypeEnum.corPA,
    lemma: 'casa',
    form: 'casa',
    category: 'noun',
    constructType: ConstructTypeEnum.vocab,
    metadata: ConstructUseMetaData(
      roomId: '!room:fakeServer.notExisting',
      timeStamp: DateTime.utc(2026, 1, 1),
    ),
    xp: xp,
  );

  Future<BuildContext> pump(WidgetTester tester, Brightness brightness) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: const Scaffold(),
      ),
    );
    return tester.element(find.byType(Scaffold));
  }

  for (final brightness in Brightness.values) {
    testWidgets('positive XP wears the theme gold ($brightness)', (
      tester,
    ) async {
      final context = await pump(tester, brightness);
      expect(
        use(5).pointValueColor(context),
        PangeaColors.of(brightness).goldFixedDim,
      );
    });
  }

  testWidgets('negative XP stays red in both themes', (tester) async {
    expect(
      use(-2).pointValueColor(await pump(tester, Brightness.light)),
      Colors.red,
    );
    expect(
      use(-2).pointValueColor(await pump(tester, Brightness.dark)),
      Colors.red,
    );
  });

  testWidgets('zero XP is neither gold nor red', (tester) async {
    final context = await pump(tester, Brightness.dark);
    expect(
      use(0).pointValueColor(context),
      Theme.of(context).colorScheme.primary,
    );
  });
}
