import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_style/color_theme_picker.dart';
import 'package:fluffychat/routes/settings/settings_style/settings_style.dart';

/// Coverage for #7758: the accent-colour swatches on settings > change your
/// style show every row at once, so the grid must not be a scrollable of its
/// own. Left scrollable it swallowed drags that belong to the page, which on a
/// narrow phone reads as a stuck screen.
void main() {
  const narrowPhone = Size(360, 640);

  /// Mounts the picker the way the settings page does: inside the page-level
  /// scroll view, with a tall sibling below so the page itself has somewhere
  /// to scroll.
  Future<ScrollController> pumpPicker(
    WidgetTester tester, {
    Color? systemColor,
    Color? currentColor,
    void Function(Color?)? onColorSelected,
  }) async {
    final controller = ScrollController();
    tester.view.physicalSize = narrowPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ColorThemePicker(
                  systemColor: systemColor,
                  currentColor: currentColor,
                  onColorSelected: onColorSelected ?? (_) {},
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('the swatch grid is not independently scrollable', (
    tester,
  ) async {
    await pumpPicker(tester);

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.physics, isA<NeverScrollableScrollPhysics>());
    expect(grid.shrinkWrap, isTrue);
  });

  testWidgets('dragging on the swatches scrolls the page', (tester) async {
    final page = await pumpPicker(tester);
    expect(page.offset, 0.0);

    await tester.drag(find.byType(GridView), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(page.offset, greaterThan(0.0));
  });

  testWidgets('every swatch is laid out, none clipped away', (tester) async {
    await pumpPicker(tester);

    // No system colour, so the "system theme" (null) swatch is dropped.
    final expected = SettingsStyleController.customColors
        .where((c) => c != null)
        .length;
    expect(find.byType(InkWell), findsNWidgets(expected));

    final gridSize = tester.getSize(find.byType(GridView));
    for (final swatch in find.byType(InkWell).evaluate()) {
      final box = swatch.renderObject! as RenderBox;
      final bottom =
          box.localToGlobal(Offset.zero, ancestor: null).dy + box.size.height;
      expect(bottom, lessThanOrEqualTo(gridSize.height + 1));
    }
  });

  testWidgets('tapping a swatch reports the colour', (tester) async {
    Color? picked;
    await pumpPicker(tester, onColorSelected: (color) => picked = color);

    await tester.tap(find.byType(InkWell).last);
    await tester.pump();

    expect(picked, SettingsStyleController.customColors.last);
  });
}
