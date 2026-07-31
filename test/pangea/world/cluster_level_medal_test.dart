import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/widgets/users/level_ribbon.dart';

/// The web cluster's level medal shows hover and the open Level panel in the
/// shield's OWN gold (#8067). The trackers beside it use a translucent gold
/// wash on a circle; behind a solid gold shield that wash is gold on gold, and
/// around it it reads as a stray circle — so the medal changes color instead.
void main() {
  Future<void> pumpMedal(
    WidgetTester tester, {
    bool selected = false,
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: ClusterLevelMedal(
              level: 3,
              selected: selected,
              onTap: onTap ?? () {},
            ),
          ),
        ),
      ),
    );
    // The L10n delegates load asynchronously; one pump isn't enough for the
    // medal to mount (same as the other cluster tests).
    await tester.pumpAndSettle();
  }

  Color? ribbonColor(WidgetTester tester) =>
      tester.widget<LevelRibbon>(find.byType(LevelRibbon)).color;

  BuildContext contextOf(WidgetTester tester) =>
      tester.element(find.byType(Scaffold));

  group('ClusterLevelMedal', () {
    testWidgets('wears the default gold at rest', (tester) async {
      await pumpMedal(tester);

      expect(ribbonColor(tester), isNull);
    });

    testWidgets('deepens its gold while hovered, and back on exit', (
      tester,
    ) async {
      await pumpMedal(tester);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(ClusterLevelMedal))),
      );
      await tester.pump();
      expect(
        ribbonColor(tester),
        AppConfig.goldHighlightByTheme(contextOf(tester)),
      );

      await tester.sendEventToBinding(pointer.hover(Offset.zero));
      await tester.pump();
      expect(ribbonColor(tester), isNull);
    });

    testWidgets('stays in the deepened gold while the Level panel is open', (
      tester,
    ) async {
      await pumpMedal(tester, selected: true);

      expect(
        ribbonColor(tester),
        AppConfig.goldHighlightByTheme(contextOf(tester)),
      );
    });

    testWidgets('never paints a circle behind or around the shield', (
      tester,
    ) async {
      // The regression #8067 names: a hover wash and a sticky selected wash,
      // both circles under the medal. Neither may come back — in either state.
      for (final selected in [false, true]) {
        await pumpMedal(tester, selected: selected);

        expect(
          tester.widget<InkWell>(find.byType(InkWell)).hoverColor,
          Colors.transparent,
        );
        expect(
          find.descendant(
            of: find.byType(ClusterLevelMedal),
            matching: find.byWidgetPredicate(
              (w) =>
                  (w is Ink && w.decoration != null) ||
                  (w is Container && w.decoration != null) ||
                  (w is DecoratedBox),
            ),
          ),
          findsNothing,
        );
      }
    });

    testWidgets('still opens the Level panel when tapped', (tester) async {
      var taps = 0;
      await pumpMedal(tester, onTap: () => taps++);

      await tester.tap(find.byType(ClusterLevelMedal));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
