import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/activity_tile_body.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// #8278 — a live session's world-map large card and its Chats-list tile share
/// one body so the two can never drift (world-map.instructions.md, "Pin
/// display"). This covers what that body owes both hosts.
void main() {
  // Avatar reads the bot name out of the environment to spot the bot's own
  // avatar, and an unloaded dotenv throws before it can paint.
  setUpAll(() => dotenv.testLoad(mergeWith: {}));

  Future<void> pump(
    WidgetTester tester, {
    Widget? preview,
    int starsTotal = 0,
    int starsEarned = 0,
    bool reserveStarSpace = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: ActivityTileBody(
                room: null,
                preview: preview,
                starsTotal: starsTotal,
                starsEarned: starsEarned,
                reserveStarSpace: reserveStarSpace,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The height the star row is laid out in — what stops a hydrating total from
  /// resizing the card underneath it.
  double starRowBoxHeight(WidgetTester tester) => tester
      .widget<SizedBox>(
        find
            .ancestor(
              of: find.byType(ActivityStarRow),
              matching: find.byType(SizedBox),
            )
            .first,
      )
      .height!;

  testWidgets('the host supplies the preview text; the body supplies the '
      'sender avatar beside it', (tester) async {
    // The two hosts resolve the last event differently — the chat list through
    // Pangea display text, the map through the SDK fallback — so the text is
    // passed in and only the frame around it is shared.
    await pump(tester, preview: const Text('nos vemos en el estadio'));
    expect(find.text('nos vemos en el estadio'), findsOneWidget);
    expect(find.byType(Avatar), findsOneWidget);
  });

  testWidgets('a card with no room and no preview shows no avatar', (
    tester,
  ) async {
    await pump(tester, starsTotal: 3);
    expect(find.byType(Avatar), findsNothing);
    expect(find.byType(ActivityStarRow), findsOneWidget);
  });

  testWidgets('the star row shows earned of total', (tester) async {
    await pump(tester, starsTotal: 4, starsEarned: 2);
    final row = tester.widget<ActivityStarRow>(find.byType(ActivityStarRow));
    expect(row.total, 4);
    expect(row.earned, 2);
  });

  testWidgets('more earned than the current total clamps to the total', (
    tester,
  ) async {
    // An owner edit can drop a goal the learner had already been awarded, so
    // earned can outrun the total; the row must not draw a 5th of 3 stars.
    await pump(tester, starsTotal: 3, starsEarned: 5);
    expect(
      tester.widget<ActivityStarRow>(find.byType(ActivityStarRow)).earned,
      3,
    );
  });

  testWidgets('a total past the readable count condenses to a "n/m" count', (
    tester,
  ) async {
    await pump(tester, starsTotal: 13, starsEarned: 4);
    expect(
      tester.widget<ActivityStarRow>(find.byType(ActivityStarRow)).condensed,
      isTrue,
    );
  });

  group('star-row space', () {
    testWidgets('the map holds the row height with no stars yet, so a '
        'hydrating total cannot make the card jump', (tester) async {
      await pump(tester, starsTotal: 0);
      expect(find.byType(ActivityStarRow), findsOneWidget);
      expect(starRowBoxHeight(tester), 16);
    });

    testWidgets('the chat list drops the row entirely with no stars, rather '
        'than holding an empty band under the tile', (tester) async {
      await pump(tester, starsTotal: 0, reserveStarSpace: false);
      expect(find.byType(ActivityStarRow), findsNothing);
    });

    testWidgets('the chat list still draws the row once there are stars', (
      tester,
    ) async {
      await pump(
        tester,
        starsTotal: 3,
        starsEarned: 1,
        reserveStarSpace: false,
      );
      expect(find.byType(ActivityStarRow), findsOneWidget);
    });
  });
}
