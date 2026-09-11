import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';

/// The XP a use is worth is drawn in the theme's text gold, not a hard-coded
/// hex (#8491): [PangeaColors.gold], which clears 4.5:1 on the surface in both
/// brightnesses.
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
      expect(use(5).pointValueColor(context), PangeaColors.of(brightness).gold);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('negative XP wears the theme error colour ($brightness)', (
      tester,
    ) async {
      final context = await pump(tester, brightness);
      expect(
        use(-2).pointValueColor(context),
        Theme.of(context).colorScheme.error,
      );
    });
  }

  testWidgets('zero XP is neither gold nor red', (tester) async {
    final context = await pump(tester, Brightness.dark);
    expect(
      use(0).pointValueColor(context),
      Theme.of(context).colorScheme.primary,
    );
  });
}
