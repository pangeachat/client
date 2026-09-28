import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_video_keyboard_control.dart';

/// #9128 — the playing video is one named Tab stop that answers YouTube's own
/// keys, and it must stay a plain group: a button's children are hidden from
/// assistive tech on web, and the embed's frame is one of them.
void main() {
  late int playbackToggles;
  late int muteToggles;
  late int captionToggles;

  // Rings render only in traditional (keyboard) highlight mode (#8724).
  setUp(() {
    playbackToggles = 0;
    muteToggles = 0;
    captionToggles = 0;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDownAll(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Widget subject({bool captions = true, bool autofocus = false}) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          height: 180,
          child: ActivityVideoKeyboardControl(
            autofocus: autofocus,
            onTogglePlayback: () => playbackToggles++,
            onToggleMute: () => muteToggles++,
            onToggleCaptions: captions ? () => captionToggles++ : null,
            // Stands in for the player: on web its platform views bring focus
            // nodes of their own, which must not become Tab stops.
            child: TextButton(onPressed: () {}, child: const Text('inside')),
          ),
        ),
      ),
    ),
  );

  bool showsFocusRing(WidgetTester tester) =>
      tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((box) {
        final decoration = box.decoration;
        return decoration is BoxDecoration &&
            decoration.border is Border &&
            (decoration.border! as Border).top.color ==
                FocusRingTapTarget.twoToneOuter;
      });

  Future<void> tabOnto(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the player is one Tab stop with a ring, however much is inside',
    (tester) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();
      expect(showsFocusRing(tester), isFalse);

      await tabOnto(tester);
      final onControl = FocusManager.instance.primaryFocus;
      expect(showsFocusRing(tester), isTrue);

      await tabOnto(tester);
      expect(
        FocusManager.instance.primaryFocus,
        onControl,
        reason:
            'a second Tab wraps back: nothing inside the player takes focus',
      );
    },
  );

  testWidgets('Space, Enter and K play and pause', (tester) async {
    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();
    await tabOnto(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);

    expect(playbackToggles, 3);
    expect(muteToggles, 0);
    expect(captionToggles, 0);
  });

  testWidgets('M mutes and C turns captions on and off', (tester) async {
    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();
    await tabOnto(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);

    expect(muteToggles, 1);
    expect(captionToggles, 1);
    expect(playbackToggles, 0);
  });

  testWidgets('keys do nothing until the player has focus', (tester) async {
    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);

    expect(playbackToggles, 0);
    expect(muteToggles, 0);
  });

  testWidgets('a player with no captions ignores C', (tester) async {
    await tester.pumpWidget(subject(captions: false));
    await tester.pumpAndSettle();
    await tabOnto(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);

    expect(captionToggles, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'autofocus takes focus when the player replaces a pressed poster',
    (tester) async {
      await tester.pumpWidget(subject(autofocus: true));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);

      expect(playbackToggles, 1);
    },
  );

  testWidgets('it is one focusable group named Video player, never a button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();

    final named = tester.semantics
        .simulatedAccessibilityTraversal()
        .where((node) => node.getSemanticsData().label == 'Video player')
        .toList();
    expect(named, hasLength(1));
    final node = named.single;
    expect(node.flagsCollection.isFocused, isNot(Tristate.none));
    expect(node.flagsCollection.isButton, isFalse);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(
      find.bySemanticsLabel('inside'),
      findsOneWidget,
      reason: 'the player keeps its own semantics under the group',
    );
    handle.dispose();
  });
}
