import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'one_node_control.dart';

/// #8868 — a tappable [Avatar] that opts into [Avatar.focusable] is a Tab
/// stop with a visible ring, Enter activates it, and it is still one button
/// named for its owner. Tappable avatars that do not opt in, and avatars
/// with no tap at all, add no Tab stop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('avatar_focus_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('svg_cache');
    // Avatar reads Environment.botName from dotenv.
    dotenv.testLoad(mergeWith: {'BOT_NAME': '@bot:example.com'});
  });

  // Rings render only in traditional (keyboard) highlight mode (#8724).
  setUp(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDownAll(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  bool showsFocusRing(WidgetTester tester) {
    return tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((
      box,
    ) {
      final decoration = box.decoration;
      return decoration is ShapeDecoration &&
          decoration.shape is OutlinedBorder &&
          (decoration.shape as OutlinedBorder).side.width ==
              FocusRingTapTarget.ringWidth;
    });
  }

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('a focusable avatar is a Tab stop, rings, and Enter taps it', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(Avatar(name: 'Alice', onTap: () => taps++, focusable: true)),
    );
    await tester.pumpAndSettle();
    expect(showsFocusRing(tester), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(showsFocusRing(tester), isTrue, reason: 'Tab must focus it');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 1, reason: 'Enter must activate onTap');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(taps, 2, reason: 'Space must activate onTap');
  });

  testWidgets('a focusable avatar is still one button named for its owner', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      wrap(Avatar(name: 'Alice', onTap: () {}, focusable: true)),
    );
    await tester.pumpAndSettle();

    // Name, role, focus and tap on one node — the focusable half is what
    // #8870 missed (#8873).
    expectOneNodeControl(tester, 'Alice');
    handle.dispose();
  });

  testWidgets('a nameless avatar is never a Tab stop, even if asked', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(Avatar(name: '', onTap: () => taps++, focusable: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FocusRingTapTarget), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  testWidgets('avatars that do not opt in add no Tab stop', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            Avatar(name: 'Bob', onTap: () => taps++),
            const Avatar(name: 'Carol'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FocusRingTapTarget), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 0, reason: 'nothing focusable to activate');
    expect(showsFocusRing(tester), isFalse);

    // The tappable one is still exactly one button with a tap action, as
    // before this change.
    expect(find.bySemanticsLabel('Bob'), findsOneWidget);
    final bob = tester.getSemantics(find.bySemanticsLabel('Bob'));
    expect(bob.flagsCollection.isButton, isTrue);
    expect(bob.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });
}
