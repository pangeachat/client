import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/exiting_markers_layer.dart';
import 'package:fluffychat/routes/world/map_exit_tracker.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';
import 'package:fluffychat/routes/world/world_map_view.dart';

/// Regression guard for #8155: scrolling away from mid pins and back made them
/// play a few collapse/expand animations before settling.
///
/// The cause was an exit animation queued for a pin that had left the *camera*,
/// not the ranking. flutter_map's MarkerLayer culls off-screen markers, so that
/// dying pin is never built, never runs its controller and never fires
/// `onExited` — it strands in the exit tracker. Panning back builds it fresh,
/// and [WorldMapDot]'s dying branch replays the shrink from full scale, so a
/// phantom pin collapses (once per cull/reorder of the layer) before the real
/// pin finally pops in at the settle.
///
/// [MapExitTracker] fixes it by only ever animating out an item that is still
/// on screen. The widget test at the bottom pins the framework behaviour the
/// rule exists for.
void main() {
  QuestActivityCard card(String id) => QuestActivityCard(
    activityId: id,
    title: 'Activity $id',
    l2: 'es',
    coordinates: const [0, 0],
    learningObjectiveRefs: const [],
  );

  PinSnapshot snapshot(String id) => PinSnapshot(
    card: card(id),
    state: ActivityPinState.joinable,
    tier: PinTier.mid,
    pinged: false,
    starLevel: ActivityStarLevel.none,
  );

  Map<String, PinSnapshot> active(List<String> ids) => {
    for (final id in ids) id: snapshot(id),
  };

  bool alwaysOnScreen(PinSnapshot _) => true;
  bool neverOnScreen(PinSnapshot _) => false;

  List<String> idsOf(MapExitTracker<PinSnapshot> t) =>
      t.exiting.map((s) => s.card.activityId).toList();

  group('MapExitTracker exits', () {
    test('a pin ranked out while on screen plays its shrink-out', () {
      final tracker = MapExitTracker<PinSnapshot>();
      tracker.update(active: active(['a', 'b']), isOnScreen: alwaysOnScreen);

      // 'b' loses its slot (demoted past the cap, promoted to large, filtered
      // out) while still in view — that transition is what the animation is for.
      tracker.update(active: active(['a']), isOnScreen: alwaysOnScreen);

      expect(idsOf(tracker), ['b']);
    });

    test('a pin the camera scrolled away from is dropped, never queued', () {
      final tracker = MapExitTracker<PinSnapshot>();
      tracker.update(active: active(['a', 'b']), isOnScreen: alwaysOnScreen);

      // Camera pans away: both leave the render set AND the screen.
      tracker.update(active: active([]), isOnScreen: neverOnScreen);

      expect(
        idsOf(tracker),
        isEmpty,
        reason:
            'an off-screen dying marker is culled, so its exit can never play '
            'or report back — queueing it strands a phantom pin that replays '
            'its collapse when the camera comes back (#8155)',
      );
    });

    test('an exit already running is abandoned once it leaves the screen', () {
      final tracker = MapExitTracker<PinSnapshot>();
      tracker.update(active: active(['a']), isOnScreen: alwaysOnScreen);
      tracker.update(active: active([]), isOnScreen: alwaysOnScreen);
      expect(idsOf(tracker), ['a']);

      // The learner pans away mid-shrink: nothing left to watch it finish.
      tracker.update(active: active([]), isOnScreen: neverOnScreen);

      expect(idsOf(tracker), isEmpty);
    });

    test('re-entering the active set cancels an in-progress exit', () {
      final tracker = MapExitTracker<PinSnapshot>();
      tracker.update(active: active(['a']), isOnScreen: alwaysOnScreen);
      tracker.update(active: active([]), isOnScreen: alwaysOnScreen);
      expect(idsOf(tracker), ['a']);

      tracker.update(active: active(['a']), isOnScreen: alwaysOnScreen);

      expect(idsOf(tracker), isEmpty);
    });

    test('finishExit drains the pin its widget reported done', () {
      final tracker = MapExitTracker<PinSnapshot>();
      tracker.update(active: active(['a', 'b']), isOnScreen: alwaysOnScreen);
      tracker.update(active: active([]), isOnScreen: alwaysOnScreen);
      expect(idsOf(tracker), ['a', 'b']);

      tracker.finishExit('a');

      expect(idsOf(tracker), ['b']);
    });
  });

  group('MapExitTracker entries', () {
    test('a pin animates in on its first build only (#8136)', () {
      final tracker = MapExitTracker<PinSnapshot>();
      tracker.update(active: active(['a']), isOnScreen: alwaysOnScreen);

      expect(tracker.markEntered('a'), isTrue);
      expect(
        tracker.markEntered('a'),
        isFalse,
        reason:
            'a State recreated by MarkerLayer mid-gesture must render settled, '
            'not replay its pop-in (#8136)',
      );
    });

    test('a pin that leaves and returns pops in fresh again', () {
      final tracker = MapExitTracker<PinSnapshot>();
      tracker.update(active: active(['a']), isOnScreen: alwaysOnScreen);
      expect(tracker.markEntered('a'), isTrue);

      // Scrolled away (the #8155 repro), then scrolled back.
      tracker.update(active: active([]), isOnScreen: neverOnScreen);
      tracker.update(active: active(['a']), isOnScreen: alwaysOnScreen);

      expect(
        tracker.markEntered('a'),
        isTrue,
        reason: 'the returning pin must pop up cleanly, once (#8155)',
      );
    });
  });

  testWidgets(
    'a culled dying marker never builds, so its onExited never fires',
    (tester) async {
      // The framework fact the on-screen gate exists for: MarkerLayer drops
      // markers outside the camera before building them, so an off-screen
      // dying dot cannot animate or report back — it would sit in the tracker
      // until the camera returned and then replay its collapse.
      var exited = false;
      final controller = MapController();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: FlutterMap(
            mapController: controller,
            options: const MapOptions(
              initialCenter: LatLng(0, 0),
              initialZoom: 12,
            ),
            children: [
              ExitingMarkersLayer(
                // Far off screen at zoom 12 — the pin the camera left behind.
                exiting: [
                  PinSnapshot(
                    card: const QuestActivityCard(
                      activityId: 'gone',
                      title: 'Gone',
                      l2: 'es',
                      coordinates: [60, 60],
                      learningObjectiveRefs: [],
                    ),
                    state: ActivityPinState.joinable,
                    tier: PinTier.mid,
                    pinged: false,
                    starLevel: ActivityStarLevel.none,
                  ),
                ],
                markerBox: (_, _) => const Size(44, 54),
                markerAlignment: (_, _) => Alignment.center,
                onExited: (_) => exited = true,
              ).layer(),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WorldMapDot), findsNothing);
      expect(
        exited,
        isFalse,
        reason:
            'MarkerLayer culls the off-screen marker, so the exit animation '
            'never runs and never drains itself — which is why an off-screen '
            'pin must not be queued for one at all (#8155)',
      );
    },
  );
}
