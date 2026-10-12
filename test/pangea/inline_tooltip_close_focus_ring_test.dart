import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'contrast_ratio.dart';

/// #9278: the inline tooltip's close X showed keyboard focus only through
/// Material's wash, which all but vanishes on the gold fill. It now wears the
/// shared focus ring in the fill's own ink.
void main() {
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  for (final brightness in Brightness.values) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      extensions: [PangeaColors.of(brightness)],
    );

    Future<void> pumpTooltip(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(
            body: Center(
              child: InlineTooltip(
                message: 'Tap a word to see its meaning',
                isClosed: false,
                animate: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    BorderSide closeButtonSide(WidgetTester tester) {
      final material = tester.widget<Material>(
        find.descendant(
          of: find.widgetWithIcon(IconButton, Icons.close_outlined),
          matching: find.byType(Material),
        ),
      );
      return (material.shape! as OutlinedBorder).side;
    }

    testWidgets('Tab rings the close X in the tooltip ink '
        '(${brightness.name})', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await pumpTooltip(tester);
      expect(closeButtonSide(tester), BorderSide.none);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final ring = closeButtonSide(tester);
      expect(ring.color, theme.pangea.onGoldFixed);
      expect(ring.width, FocusRingTapTarget.ringWidth);
      expect(
        contrastRatio(ring.color, theme.pangea.goldFixedDim),
        greaterThanOrEqualTo(minGraphicRatio),
      );
    });

    testWidgets('no ring in touch highlight mode (${brightness.name})', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      await pumpTooltip(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(closeButtonSide(tester), BorderSide.none);
    });
  }
}
