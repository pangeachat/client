import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';

/// #9191: [PressableButton] was a bare GestureDetector, so the message
/// toolbar's round buttons were no Tab stop and no key pressed them.
void main() {
  // Rings render only in traditional (keyboard) highlight mode (#8724).
  setUp(() async {
    // The button's click player reads the volume setting.
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDownAll(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Widget wrap({required VoidCallback? onPressed, bool focusable = true}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableButton(
              borderRadius: BorderRadius.circular(20),
              color: Colors.purple,
              onPressed: onPressed,
              focusable: focusable,
              builder: (_, _, _) => const SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      );

  bool buttonHasFocus(WidgetTester tester) =>
      Focus.of(tester.element(find.byType(GestureDetector))).hasPrimaryFocus;

  bool showsFocusRing(WidgetTester tester) =>
      tester.widget<FocusRing>(find.byType(FocusRing)).show;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('is a Tab stop with a ring, and Enter and Space press it', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(wrap(onPressed: () => presses++));
    expect(showsFocusRing(tester), isFalse);

    await press(tester, LogicalKeyboardKey.tab);
    expect(buttonHasFocus(tester), isTrue);
    expect(showsFocusRing(tester), isTrue);

    await press(tester, LogicalKeyboardKey.enter);
    expect(presses, 1);
    await press(tester, LogicalKeyboardKey.space);
    expect(presses, 2);
  });

  testWidgets('a tap still presses it', (tester) async {
    var presses = 0;
    await tester.pumpWidget(wrap(onPressed: () => presses++));

    await tester.tap(find.byType(PressableButton));
    await tester.pumpAndSettle();

    expect(presses, 1);
  });

  testWidgets('is no Tab stop when it opts out', (tester) async {
    await tester.pumpWidget(wrap(onPressed: () {}, focusable: false));

    await press(tester, LogicalKeyboardKey.tab);

    expect(buttonHasFocus(tester), isFalse);
    expect(showsFocusRing(tester), isFalse);
  });

  testWidgets('is no Tab stop when it has nothing to press', (tester) async {
    await tester.pumpWidget(wrap(onPressed: null));

    await press(tester, LogicalKeyboardKey.tab);

    expect(buttonHasFocus(tester), isFalse);
  });
}
