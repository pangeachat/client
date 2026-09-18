import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/widgets/decorative_stars.dart';
import 'package:fluffychat/features/subscription/widgets/locked_shimmer_box.dart';
import 'package:fluffychat/features/subscription/widgets/unlock_button.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_summary_unsubscribed_card.dart';

/// The gate that stands in for a finished activity's summary (#8860). What is
/// worth pinning is that it is built from the shared kit and wears the
/// summary's own geometry — the two things that make it read as the feature it
/// replaces rather than a notice about it.
void main() {
  late L10n l10n;

  Future<void> pumpCard(WidgetTester tester, {int roleCount = 3}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = L10n.of(context);
            return Scaffold(
              body: SingleChildScrollView(
                child: ActivitySummaryUnsubscribedCard(roleCount: roleCount),
              ),
            );
          },
        ),
      ),
    );
    // Two frames, not pumpAndSettle: MaterialApp's localization delegates
    // resolve asynchronously, so the first frame is empty — and the skeleton's
    // shimmer never stops, so settling would spin forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('is built from the shared subscription-gate kit', (tester) async {
    await pumpCard(tester);

    // A skeleton, not a message: the gate shows the shape of what is missing.
    expect(find.byType(LockedShimmerBox), findsWidgets);
    expect(find.byType(DecorativeStars), findsOneWidget);
    expect(find.byType(UnlockButton), findsOneWidget);
  });

  testWidgets('its call to action names the feature, kit-style', (
    tester,
  ) async {
    await pumpCard(tester);

    expect(
      tester.widget<UnlockButton>(find.byType(UnlockButton)).label,
      l10n.unlockActivitySummaries,
    );
  });

  testWidgets('the button hugs its label instead of filling the card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpCard(tester);

    // The gold block spans the card's full inner width; the pill must not.
    // A label too long for one line makes its [Text] fill the constraints,
    // which turned this pill into a 538x74 band across the middle of the card
    // and made clicks land on it from most of the surface (#8860).
    final gold = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is LockedShimmerBox && w.baseColor != null,
      ),
    );
    final button = tester.getRect(find.byType(UnlockButton));

    expect(
      button.width,
      lessThan(gold.width),
      reason: 'a pill as wide as the content is a band, not a button',
    );
    expect(
      button.height,
      lessThan(60.0),
      reason: 'a two-line label doubles the pill height',
    );
  });

  testWidgets('wears the summary\'s own width cap, so it lands where the '
      'summary would', (tester) async {
    await pumpCard(tester);

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ActivitySummaryUnsubscribedCard),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      container.constraints?.maxWidth,
      FluffyThemes.columnWidth * 1.5,
      reason: 'ActivityUserSummaries caps its box at the same width',
    );
  });

  testWidgets('stands the summary itself up as a tinted block', (tester) async {
    await pumpCard(tester);

    // Every other block wears the shared placeholder wash; the summary is the
    // one that carries a tint, so the eye lands on what is withheld.
    expect(
      find.byWidgetPredicate(
        (w) => w is LockedShimmerBox && w.baseColor != null,
      ),
      findsOneWidget,
    );
  });

  group('the picker row matches the activity', () {
    Finder circles() => find.byWidgetPredicate(
      (w) => w is LockedShimmerBox && w.width == 40.0 && w.height == 40.0,
    );

    testWidgets('one circle per learner in a role', (tester) async {
      await pumpCard(tester, roleCount: 2);
      expect(circles(), findsNWidgets(2));

      await pumpCard(tester, roleCount: 5);
      expect(circles(), findsNWidgets(5));
    });

    testWidgets('no row at all rather than a wrong count', (tester) async {
      await pumpCard(tester, roleCount: 0);
      expect(circles(), findsNothing);
      // The rest of the gate still stands.
      expect(find.byType(UnlockButton), findsOneWidget);
    });
  });

  group('in the chat\'s SelectionArea, as it actually renders', () {
    /// [PressableButton] awaits its own depress animation before calling
    /// onPressed, so the navigation lands several frames after the tap.
    Future<void> settlePress(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// The timeline wraps everything in a [SelectionArea]
    /// (chat_event_list.dart), so the gate has to behave inside one.
    Future<GoRouter> pumpInSelectionArea(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: SelectionArea(
                child: ListView(
                  reverse: true,
                  children: const [
                    ActivitySummaryUnsubscribedCard(roleCount: 3),
                    SizedBox(height: 400.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return router;
    }

    testWidgets('a tap off the button does not press it', (tester) async {
      final router = await pumpInSelectionArea(tester);

      // The heading block, well above the centred pill.
      await tester.tapAt(
        tester.getCenter(
          find.byWidgetPredicate(
            (w) => w is LockedShimmerBox && w.width == 200.0,
          ),
        ),
      );
      await settlePress(tester);

      expect(
        router.state.uri.toString(),
        isNot(contains('settings')),
        reason: 'only the button itself may open the subscription page',
      );
    });

    testWidgets('the button itself still opens the subscription page', (
      tester,
    ) async {
      final router = await pumpInSelectionArea(tester);

      await tester.tap(find.byType(UnlockButton));
      await settlePress(tester);

      expect(router.state.uri.toString(), contains('settings'));
    });
  });

  testWidgets('opts out of the timeline\'s text selection, so its label does '
      'not wear an I-beam', (tester) async {
    await pumpCard(tester);

    // chat_event_list.dart wraps every row in a SelectionArea; without this
    // the gate's text is selectable and the cursor over the button's label
    // turns into a caret, which no other button does.
    expect(
      find.ancestor(
        of: find.byType(UnlockButton),
        matching: find.byType(SelectionContainer),
      ),
      findsOneWidget,
    );
  });

  testWidgets('makes the skeleton pointer-blind, so only the button is '
      'clickable', (tester) async {
    await pumpCard(tester);

    // The skeleton is a picture of content. Nothing in it should ever take a
    // pointer, and the button must NOT be inside the same blind subtree.
    // Only the gate's own wrappers — the scroll view above it carries
    // IgnorePointers of its own, and DecorativeStars carries one too.
    final blind = find.ancestor(
      of: find.byWidgetPredicate(
        (w) => w is LockedShimmerBox && w.width == 200.0,
      ),
      matching: find.descendant(
        of: find.byType(ActivitySummaryUnsubscribedCard),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(blind, findsOneWidget);
    expect(
      find.descendant(of: blind, matching: find.byType(UnlockButton)),
      findsNothing,
      reason: 'the call to action must stay outside the blind subtree',
    );
  });

  testWidgets('keeps the tap action on a node the size of the button, not the '
      'list row (#8860)', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(768, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // In a ListView, as the timeline renders it: each row is wrapped in
    // IndexedSemantics, and without an explicit boundary the gate's only
    // action — the button's — is absorbed into that ROW-sized node. Flutter
    // web paints semantics nodes as real DOM elements and dispatches a click
    // on one as a synthetic tap at the node's CENTRE, so a click anywhere in
    // the row (even beside the card) was re-aimed onto the pill and opened
    // the subscription page.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          // Captures l10n from this test's own tree, so it does not depend on
          // another test having run first.
          body: Builder(
            builder: (context) {
              l10n = L10n.of(context);
              return ListView(
                children: const [ActivitySummaryUnsubscribedCard(roleCount: 3)],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The node carrying the button's label — the same node that carries its
    // tap action. Absorbed upward, that pair lands on the row-sized node.
    final node = tester.getSemantics(
      find.bySemanticsLabel(l10n.unlockActivitySummaries),
    );
    final button = tester.getRect(find.byType(UnlockButton));

    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(
      node.rect.width,
      closeTo(button.width, 1.0),
      reason: 'a row-wide tappable node re-aims stray clicks onto the pill',
    );
    expect(node.rect.height, closeTo(button.height, 1.0));

    // Disposed inline: the framework's handle check runs before tearDowns.
    handle.dispose();
  });

  testWidgets('draws the stars behind the call to action, never over it', (
    tester,
  ) async {
    await pumpCard(tester);

    // The kit's rule: DecorativeStars is texture and is listed BEFORE what it
    // decorates, or it eats the label's contrast.
    final stack = tester.widget<Stack>(
      find
          .descendant(
            of: find.byType(ActivitySummaryUnsubscribedCard),
            matching: find.byType(Stack),
          )
          .first,
    );
    final stars = stack.children.indexWhere((w) => w is DecorativeStars);
    final button = stack.children.indexWhere((w) => w is UnlockButton);

    expect(stars, isNonNegative);
    expect(button, isNonNegative);
    expect(stars, lessThan(button));
  });
}
