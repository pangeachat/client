import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_card.dart';

/// #8823 — the writing assistance card's header. Listen First is the one action
/// with a place in the header itself; everything else lives behind the overflow
/// menu. The category name is what the learner opened the card to read, so when
/// it cannot sit beside both, Listen First folds into the menu too.
/// See writing-assistance.instructions.md § Header actions and width.
void main() {
  late List<String> listenToggles;
  late int autoIGCToggles;
  late int feedbackTaps;
  late int settingsTaps;
  late int closeTaps;

  setUp(() {
    listenToggles = [];
    autoIGCToggles = 0;
    feedbackTaps = 0;
    settingsTaps = 0;
    closeTaps = 0;
  });

  Future<void> pumpHeader(
    WidgetTester tester, {
    required String title,
    required double width,
    bool listenFirst = false,
    bool showListenFirst = true,
    bool autoIGC = true,
    String targetId = 'wa-listen-test',
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
                targetId: targetId,
                title: title,
                showListenFirst: showListenFirst,
                listenFirst: listenFirst,
                autoIGC: autoIGC,
                onToggleListenFirst: listenToggles.add,
                onToggleAutoIGC: () => autoIGCToggles++,
                onFeedback: () => feedbackTaps++,
                onLearningSettings: () => settingsTaps++,
                onClose: () => closeTaps++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
  }

  // Close, Listen First and the menu leave 256pt for the title at 400pt wide,
  // which "Spelling" clears easily and "Subject Verb Agreement" does not.
  const shortTitle = 'Spelling';
  const longTitle = 'Subject Verb Agreement';

  group('header layout', () {
    testWidgets('the menu is always there, and the flag never is', (
      tester,
    ) async {
      await pumpHeader(tester, title: shortTitle, width: 400);

      expect(find.byTooltip('More options'), findsOneWidget);
      expect(find.byTooltip('Submit feedback'), findsNothing);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
    });

    testWidgets('Listen First sits in the header when the title leaves room', (
      tester,
    ) async {
      await pumpHeader(tester, title: shortTitle, width: 400);

      expect(find.byTooltip('Listen first'), findsOneWidget);
    });

    testWidgets('Listen First folds into the menu when it does not', (
      tester,
    ) async {
      await pumpHeader(tester, title: longTitle, width: 400);

      expect(find.byTooltip('Listen first'), findsNothing);
      // The title is what the fold bought room for.
      expect(find.text(longTitle), findsOneWidget);

      await openMenu(tester);
      expect(find.text('Listen first'), findsOneWidget);
    });

    testWidgets('the same title goes either way on the width it is given', (
      tester,
    ) async {
      await pumpHeader(tester, title: longTitle, width: 400);
      expect(find.byTooltip('Listen first'), findsNothing);

      await pumpHeader(tester, title: longTitle, width: 800);
      expect(find.byTooltip('Listen first'), findsOneWidget);
    });

    // An accepted match shows a diff and an undo, so there is nothing to hear.
    testWidgets('an accepted match offers no Listen First at all', (
      tester,
    ) async {
      await pumpHeader(
        tester,
        title: shortTitle,
        width: 400,
        showListenFirst: false,
      );

      expect(find.byTooltip('Listen first'), findsNothing);
      await openMenu(tester);
      expect(find.text('Listen first'), findsNothing);
      // The rest of the menu is unaffected.
      expect(find.text('Report content issue'), findsOneWidget);
    });

    testWidgets('close is always reachable', (tester) async {
      await pumpHeader(tester, title: longTitle, width: 400);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(closeTaps, 1);
    });
  });

  group('overflow menu', () {
    testWidgets('holds the auto-run toggle, report and settings', (
      tester,
    ) async {
      await pumpHeader(tester, title: shortTitle, width: 400);
      await openMenu(tester);

      expect(find.text('Enable writing assistance'), findsOneWidget);
      expect(find.text('Report content issue'), findsOneWidget);
      expect(find.text('Learning settings'), findsOneWidget);
    });

    testWidgets('checks the modes that are on, and not the trips', (
      tester,
    ) async {
      await pumpHeader(
        tester,
        title: longTitle,
        width: 400,
        listenFirst: true,
        autoIGC: true,
      );
      await openMenu(tester);

      // One per mode — reporting and settings are actions, not states.
      expect(find.byIcon(Icons.check), findsNWidgets(2));
    });

    testWidgets('leaves a mode that is off unchecked', (tester) async {
      await pumpHeader(tester, title: shortTitle, width: 400, autoIGC: false);
      await openMenu(tester);

      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('each entry fires its own action', (tester) async {
      await pumpHeader(tester, title: shortTitle, width: 400);

      await openMenu(tester);
      await tester.tap(find.text('Enable writing assistance'));
      await tester.pumpAndSettle();
      expect(autoIGCToggles, 1);

      await openMenu(tester);
      await tester.tap(find.text('Report content issue'));
      await tester.pumpAndSettle();
      expect(feedbackTaps, 1);

      await openMenu(tester);
      await tester.tap(find.text('Learning settings'));
      await tester.pumpAndSettle();
      expect(settingsTaps, 1);
    });

    testWidgets('the folded Listen First entry toggles it', (tester) async {
      await pumpHeader(tester, title: longTitle, width: 400);
      await openMenu(tester);
      await tester.tap(find.text('Listen first'));
      await tester.pumpAndSettle();

      expect(listenToggles, ['wa-listen-test']);
    });
  });
}
