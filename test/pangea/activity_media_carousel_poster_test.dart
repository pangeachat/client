import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_carousel.dart';
import 'one_node_control.dart';

/// #9128 — a video's thumbnail is how the keyboard starts it: one button named
/// "Play video" that Tab reaches. It was a bare GestureDetector, so Tab skipped
/// it and a screen reader heard only "button".
void main() {
  // No thumbnail URL, so the poster renders its placeholder and the test needs
  // no network.
  const video = ActivityMediaBlock(blockType: 'video');

  Widget subject() => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: const Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: ActivityMediaCarousel(media: [video]),
        ),
      ),
    ),
  );

  testWidgets('the thumbnail is one button named Play video', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();

    expectOneNodeControl(tester, 'Play video');
    handle.dispose();
  });

  testWidgets('Tab reaches the thumbnail', (tester) async {
    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      focused?.findAncestorWidgetOfExactType<ActivityMediaCarousel>(),
      isNotNull,
      reason: 'keyboard focus is on the thumbnail inside the carousel',
    );
  });
}
