import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/world/world_map_pinged_badge.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The recruiting-host badge's visual contract (#8484, world-map.instructions.md
/// "Pin state"): the same white bell on the same joinable green the course plan
/// puts on a pinged card, so one ping looks like one thing wherever the learner
/// meets it. The white ring is load-bearing rather than decorative — the
/// joinable pin beneath the badge carries this exact green, so without the ring
/// the badge dissolves into the pin it is meant to mark.
void main() {
  Future<BoxDecoration> pumpBadge(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WorldMapPingedBadge())),
    );
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(WorldMapPingedBadge),
        matching: find.byType(Container),
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  Icon badgeIcon(WidgetTester tester) => tester.widget<Icon>(
    find.descendant(
      of: find.byType(WorldMapPingedBadge),
      matching: find.byType(Icon),
    ),
  );

  testWidgets('the badge is a white bell, not the retired waving hand', (
    tester,
  ) async {
    await pumpBadge(tester);

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.byIcon(Icons.waving_hand), findsNothing);
    expect(badgeIcon(tester).color, Colors.white);
  });

  testWidgets('the circle is a white-ringed green disc', (tester) async {
    final decoration = await pumpBadge(tester);

    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, AppConfig.green);
    expect(decoration.border!.top.color, Colors.white);
  });

  testWidgets('the fill tracks the joinable pin it marks', (tester) async {
    final decoration = await pumpBadge(tester);

    expect(decoration.color, ActivityPinState.joinable.color);
  });
}
