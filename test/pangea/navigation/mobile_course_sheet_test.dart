import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/mobile_course_sheet.dart';

/// Regression coverage for #7102 ("Can't expand course page on narrow screen"):
/// the grab handle's drag/tap must actually resize the bottom sheet.
///
/// Root cause: a `DraggableScrollableController` only ATTACHES once a scrollable
/// consumes the `scrollController` the sheet's builder provides. The builder
/// returned a plain `Column` that ignored it, so `isAttached` stayed false and
/// every `animateTo`/`jumpTo` from the handle gestures silently no-opped — the
/// handle rendered but did nothing. The fix binds the content to that controller
/// (a non-scrolling `CustomScrollView`), so the handle drives resize as intended.
///
/// The handle's y is the sheet's top edge: a bigger sheet means a lower y.
void main() {
  // Each test starts from a clean expand-memory so a prior test's expanded
  // course doesn't leak into the next sheet's initial size (#7332).
  setUp(MobileCourseSheet.resetExpandedMemoryForTest);

  Future<void> pumpSheet(
    WidgetTester tester, {
    String sheetId = 'course-a',
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: MobileCourseSheet(
            sheetId: sheetId,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Drop the sheet from the tree (as opening a chat over it does), disposing its
  // State, so the next pumpSheet is a genuinely fresh mount. Keep the same L10n
  // delegates so swapping the body doesn't force Localizations to re-resolve.
  Future<void> unmountSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('drag up on the handle expands the sheet (peek → full)', (
    tester,
  ) async {
    await pumpSheet(tester);
    final handle = find.byType(GestureDetector);
    expect(handle, findsOneWidget);
    final peekY = tester.getTopLeft(handle).dy;
    await tester.drag(handle, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(handle).dy,
      lessThan(peekY),
      reason: 'dragging the handle up must grow the sheet (#7102)',
    );
  });

  testWidgets('drag down on the handle collapses the sheet (full → peek)', (
    tester,
  ) async {
    await pumpSheet(tester);
    final handle = find.byType(GestureDetector);
    await tester.tap(handle); // expand to full first
    await tester.pumpAndSettle();
    final fullY = tester.getTopLeft(handle).dy;
    await tester.drag(handle, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(handle).dy,
      greaterThan(fullY),
      reason: 'dragging the handle down must shrink the sheet (#7102)',
    );
  });

  testWidgets('tap on the handle toggles peek ↔ full', (tester) async {
    await pumpSheet(tester);
    final handle = find.byType(GestureDetector);
    final peekY = tester.getTopLeft(handle).dy;
    await tester.tap(handle);
    await tester.pumpAndSettle();
    final fullY = tester.getTopLeft(handle).dy;
    expect(fullY, lessThan(peekY), reason: 'tap expands to full');
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(handle).dy,
      greaterThan(fullY),
      reason: 'tapping again collapses back to peek',
    );
  });

  // #7332: opening a chat over the sheet disposes it; on close the sheet is a
  // fresh mount. It must reopen at the size the learner left THIS course at,
  // and a different course must still open at peek (the "Per course" decision).
  testWidgets('the same course reopens at the size it was left at (#7332)', (
    tester,
  ) async {
    await pumpSheet(tester, sheetId: 'course-a');
    final peekY = tester.getTopLeft(find.byType(GestureDetector)).dy;
    await tester.tap(find.byType(GestureDetector)); // expand
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(GestureDetector)).dy, lessThan(peekY));

    await unmountSheet(tester); // a chat opens over it → State disposed
    await pumpSheet(tester, sheetId: 'course-a'); // chat closed → fresh mount

    expect(
      tester.getTopLeft(find.byType(GestureDetector)).dy,
      lessThan(peekY),
      reason: 'the same course reopens expanded, not snapped back to peek',
    );
  });

  testWidgets('a different course opens at peek, not the last one\'s size', (
    tester,
  ) async {
    await pumpSheet(tester, sheetId: 'course-a');
    final peekY = tester.getTopLeft(find.byType(GestureDetector)).dy;
    await tester.tap(find.byType(GestureDetector)); // expand course-a
    await tester.pumpAndSettle();

    await unmountSheet(tester);
    await pumpSheet(tester, sheetId: 'course-b'); // a DIFFERENT course

    expect(
      tester.getTopLeft(find.byType(GestureDetector)).dy,
      peekY,
      reason: 'expand memory is per-course; a fresh course starts at peek',
    );
  });
}
