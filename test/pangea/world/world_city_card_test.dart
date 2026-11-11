import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_view_cards.dart';
import 'package:fluffychat/routes/world/world_view_items.dart';

/// Counts plan reads and never answers, so the card stays on its loading
/// slides.
class _CountingPlans extends CityCardPlans {
  final List<String> reads = [];

  @override
  ActivityPlanModel? cached(String activityId) => null;

  @override
  Future<ActivityPlanModel?> read(String activityId) {
    reads.add(activityId);
    return Completer<ActivityPlanModel?>().future;
  }
}

void main() {
  testWidgets(
    'a city card reads the slide on show and the next, then one more per turn',
    (tester) async {
      final plans = _CountingPlans();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: WorldCityCard(
              city: const WorldCity(
                key: 'oax',
                name: 'Oaxaca',
                point: LatLng(17.06, -96.72),
                shipRoomIds: [],
                xp: 0,
              ),
              activityIds: [for (var i = 0; i < 40; i++) 'a$i'],
              onExplore: () {},
              onOpenActivity: (_) {},
              onDismiss: () {},
              plans: plans,
            ),
          ),
        ),
      );
      // The localizations load before the card first builds; its loading
      // slide spins, so the tree never settles.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(WorldCityCard), findsOneWidget);
      expect(plans.reads, ['a0', 'a1']);

      await tester.pump(const Duration(seconds: 5));
      expect(plans.reads, ['a0', 'a1', 'a2']);
    },
  );
}
