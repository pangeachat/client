import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_card.dart';

/// #8823 — the writing assistance card's header. The category name is what the
/// learner opened the card to read, so the two actions yield to it: when the
/// measured title cannot sit beside them, both collapse into an overflow menu.
/// See writing-assistance.instructions.md § Header actions and width.
void main() {
  late List<String> listenToggles;
  late int feedbackTaps;
  late int closeTaps;

  setUp(() {
    listenToggles = [];
    feedbackTaps = 0;
    closeTaps = 0;
  });

  Future<void> pumpHeader(
    WidgetTester tester, {
    required String title,
    required double width,
    bool listenFirst = false,
    bool showListenFirst = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SpanCardHeader(
                title: title,
                showListenFirst: showListenFirst,
                listenFirst: listenFirst,
                onToggleListenFirst: listenToggles.add,
                onFeedback: () => feedbackTaps++,
                onClose: () => closeTaps++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Three 48pt icon buttons leave 256pt for the title at 400pt wide, which
  // "Spelling" clears easily and "Subject Verb Agreement" does not.
  const shortTitle = 'Spelling';
  const longTitle = 'Subject Verb Agreement';

  group('header actions', () {
    testWidgets('both actions sit in the header when the title leaves room', (
      tester,
    ) async {
      await pumpHeader(tester, title: shortTitle, width: 400);

      expect(find.byTooltip('Listen first'), findsOneWidget);
      expect(find.byTooltip('Submit feedback'), findsOneWidget);
      expect(find.byTooltip('More options'), findsNothing);
    });

    testWidgets('both collapse into the menu when the title does not', (
      tester,
    ) async {
      await pumpHeader(tester, title: longTitle, width: 400);

      expect(find.byTooltip('More options'), findsOneWidget);
      expect(find.byTooltip('Listen first'), findsNothing);
      expect(find.byTooltip('Submit feedback'), findsNothing);
      // The title is what the collapse bought room for.
      expect(find.text(longTitle), findsOneWidget);
    });

    testWidgets('the same title collapses or not by the width it is given', (
      tester,
    ) async {
      await pumpHeader(tester, title: longTitle, width: 400);
      expect(find.byTooltip('More options'), findsOneWidget);

      await pumpHeader(tester, title: longTitle, width: 800);
      expect(find.byTooltip('More options'), findsNothing);
      expect(find.byTooltip('Listen first'), findsOneWidget);
    });

    testWidgets('the menu holds both actions, and marks Listen First on', (
      tester,
    ) async {
      await pumpHeader(tester, title: longTitle, width: 400, listenFirst: true);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Listen first'), findsOneWidget);
      expect(find.text('Submit feedback'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.tap(find.text('Submit feedback'));
      await tester.pumpAndSettle();
      expect(feedbackTaps, 1);
    });

    testWidgets('the menu toggles Listen First', (tester) async {
      await pumpHeader(tester, title: longTitle, width: 400);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listen first'));
      await tester.pumpAndSettle();

      expect(listenToggles, hasLength(1));
    });

    // An accepted match shows a diff and an undo, so there is nothing to hear.
    testWidgets('an accepted match keeps the flag inline and drops the '
        'toggle', (tester) async {
      await pumpHeader(
        tester,
        title: longTitle,
        width: 400,
        showListenFirst: false,
      );

      expect(find.byTooltip('Listen first'), findsNothing);
      // One icon always fits beside a title that can ellipsize, so a
      // one-item overflow menu is never worth making.
      expect(find.byTooltip('More options'), findsNothing);
      expect(find.byTooltip('Submit feedback'), findsOneWidget);
    });

    testWidgets('close is always reachable', (tester) async {
      await pumpHeader(tester, title: longTitle, width: 400);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(closeTaps, 1);
    });
  });
}
