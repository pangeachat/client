import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_video_close_button.dart';
import 'contrast_ratio.dart';

/// #9280: the X over a playing activity video showed focus only through
/// Material's wash, invisible on the black letterbox.
void main() {
  setUp(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDownAll(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  for (final brightness in Brightness.values) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8560E0),
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      ),
      extensions: [PangeaColors.of(brightness)],
    );

    group('ActivityVideoCloseButton (${brightness.name})', () {
      var closed = 0;

      Future<void> pumpClose(WidgetTester tester) async {
        closed = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: ColoredBox(
                color: Colors.black,
                child: ActivityVideoCloseButton(onPressed: () => closed++),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      BorderSide ringOf(WidgetTester tester) {
        final material = tester.widget<Material>(
          find.descendant(
            of: find.byType(IconButton),
            matching: find.byType(Material),
          ),
        );
        return (material.shape! as OutlinedBorder).side;
      }

      testWidgets('Tab rings the X and Enter closes', (tester) async {
        await pumpClose(tester);
        expect(ringOf(tester), BorderSide.none);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(ringOf(tester).color, theme.pangea.goldGraphic);
        expect(ringOf(tester).width, FocusRingTapTarget.ringWidth);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(closed, 1);
      });

      testWidgets('no ring in touch highlight mode', (tester) async {
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTouch;
        await pumpClose(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(ringOf(tester), BorderSide.none);
      });

      test('the gold ring clears 3:1 on the black letterbox', () {
        expect(
          contrastRatio(theme.pangea.goldGraphic, Colors.black),
          greaterThanOrEqualTo(minGraphicRatio),
        );
      });
    });
  }
}
