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

  Future<void> pump(WidgetTester tester, {Widget? preview}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: ActivityTileBody(room: null, preview: preview),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the host supplies the preview text; the body supplies the '
      'sender avatar beside it', (tester) async {
    // The two hosts resolve the last event differently — the chat list through
    // Pangea display text, the map through the SDK fallback — so the text is
    // passed in and only the frame around it is shared.
    await pump(tester, preview: const Text('nos vemos en el estadio'));
    expect(find.text('nos vemos en el estadio'), findsOneWidget);
    expect(find.byType(Avatar), findsOneWidget);
  });

  testWidgets('a card with no room and no preview draws nothing', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(Avatar), findsNothing);
  });

  testWidgets('the body carries no goal row (#9559): goals live in the '
      "session's own goal header", (tester) async {
    await pump(tester, preview: const Text('hola'));
    expect(find.byType(ActivityStarRow), findsNothing);
  });
}
