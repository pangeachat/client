import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/app_section.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/mobile_nav_widget.dart';

/// Regression coverage for the cavity actually PAINTING its hosted surface.
/// The real cavity children (the chat list, the Courses hub) are the same
/// WorkspaceLeftPanel surfaces the wide layout renders: a header Column with
/// an Expanded body that nests its own Scaffold + scrollables. Live QA found
/// the cavity showing only the header with the body's nodes present in
/// semantics but never painted — this pins the structural contract.
void main() {
  setUp(() {
    MobileNavWidget.resetHeightMemoryForTest();
    // The final tap IS the paint == hit-test assertion — a missed hit must
    // fail, not warn (an overlay swallowing the tap is exactly the bug).
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  tearDown(() {
    WidgetController.hitTestWarningShouldBeFatal = false;
  });

  /// Mimics LeftPanelChatListSubpage: header + Expanded(nested Scaffold with
  /// its own scrolling body and a FAB) — the shape that failed to paint.
  Widget subpageLike() => Column(
    children: [
      const SizedBox(height: 40, child: Text('HEADER')),
      Expanded(
        child: Scaffold(
          body: ListView(
            children: const [
              SizedBox(height: 40, child: Text('ROW-1')),
              SizedBox(height: 40, child: Text('ROW-2')),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {},
            label: const Text('FAB'),
          ),
        ),
      ),
    ],
  );

  testWidgets('the cavity paints a nested-Scaffold scrollable child', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              // The shell's mounting: Positioned.fill, widget bottom-aligns.
              Positioned.fill(
                child: MobileNavWidget(
                  activeSection: AppSection.chats,
                  courseShortcutLabel: 'course',
                  onCourseShortcutTap: () {},
                  onSectionTap: (_) {},
                  cavityChild: subpageLike(),
                  cavityKey: 'chats',
                  maxHeightFraction: 0.75,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The child's header AND its nested-Scaffold body content must be hit-
    // testable on screen — not just present in the tree.
    expect(find.text('HEADER'), findsOneWidget);
    expect(find.text('ROW-1'), findsOneWidget);
    expect(find.text('FAB'), findsOneWidget);

    final row = tester.getRect(find.text('ROW-1'));
    final screen = tester.getRect(find.byType(MaterialApp));
    expect(
      screen.contains(row.center),
      isTrue,
      reason: 'the list row must be laid out within the visible screen',
    );

    // And genuinely tappable where it claims to be (paint == hit-test).
    await tester.tap(find.text('ROW-1'));
  });
}
