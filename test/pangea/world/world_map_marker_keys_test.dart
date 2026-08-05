import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/dot_markers_layer.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';

/// Regression guard for #7947 × #8136.
///
/// At minimum zoom the map is narrower than the screen, so MarkerLayer emits
/// each marker once per visible world copy — as sibling Positioned widgets in
/// ONE Stack. A key on [Marker.key] therefore duplicates and crashes (#7947,
/// which removed all marker keys). #8136 restored identity by keying the
/// marker's CHILD instead: child keys live one level down, each inside its own
/// Positioned subtree, so world copies can never collide as siblings. This
/// test pins both halves: multiple world copies render, and no duplicate-key
/// FlutterError is thrown — including across a camera move.
void main() {
  const cards = [
    QuestActivityCard(
      activityId: 'a1',
      title: 'Activity One',
      l2: 'es',
      coordinates: [0, 10],
      learningObjectiveRefs: [],
    ),
    QuestActivityCard(
      activityId: 'a2',
      title: 'Activity Two',
      l2: 'es',
      coordinates: [20, -10],
      learningObjectiveRefs: [],
    ),
  ];

  MarkerLayer dotLayer() => DotMarkersLayer(
    nonLargeCards: cards,
    tierOf: (_) => PinTier.mid,
    stateOf: (_) => ActivityPinState.available,
    starLevelOf: (_) => ActivityStarLevel.none,
    nonStartableOf: (_) => false,
    pingedOf: (_) => false,
    activeActivityInstance: null,
    markerBox: (_, _) => const Size(44, 54),
    markerAlignment: (_, _) => Alignment.center,
    focusedId: null,
    onTap: (_) {},
    animateInOf: (_) => true,
    sessionParticipants: (_, _) => (participants: const [], openSlots: 0),
  ).layer();

  testWidgets(
    'child-keyed markers survive the multi-world-copy view and a camera move',
    (tester) async {
      final controller = MapController();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: FlutterMap(
            mapController: controller,
            options: const MapOptions(
              // Zoom 0: the whole world is 256px in an 800px test surface, so
              // MarkerLayer repeats it — the exact #7947 crash scenario.
              initialCenter: LatLng(0, 0),
              initialZoom: 0,
              minZoom: 0,
            ),
            children: [dotLayer()],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'keys on marker CHILDREN must not duplicate across world copies '
            '(#7947) — only Marker.key does',
      );
      expect(
        find.byType(WorldMapDot),
        findsAtLeast(3),
        reason:
            'the world must actually be repeating (each activity rendered in '
            'multiple world copies) for this regression test to mean anything',
      );

      // Pan across the antimeridian seam — world-copy membership changes,
      // exercising the per-frame cull/reorder path that #8136 fixes.
      controller.move(const LatLng(0, 180), 0);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(WorldMapDot), findsAtLeast(3));
    },
  );
}
