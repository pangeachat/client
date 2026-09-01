import 'dart:ui' as ui show SemanticsHitTestBehavior;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/pin_semantics_layer.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// Covers #7591 at the COMPOSED level — the level the standalone pin tests in
/// world_map_semantics_activation_test.dart cannot see. The map subtree is
/// ExcludeSemantics'd (#8013, permanent — upstream declined the fix in
/// fleaflet/flutter_map#2236), which drops the pins' own semantics; the
/// [PinSemanticsLayer] mirror re-authors them outside the excluded subtree.
/// These tests pump the same composition the view builds (excluded FlutterMap
/// below, mirror above) and assert both halves of the contract: pins are
/// announced and activatable through semantics, and no viewport-sized tappable
/// node exists to blanket DOM embeds.
void main() {
  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Test Activity',
    l2: 'es',
    // [longitude, latitude] — dead center of the initial camera below.
    coordinates: [0, 0],
    learningObjectiveRefs: [],
  );

  Widget composed({
    required MapController controller,
    required void Function(QuestActivityCard) onTap,
  }) {
    return MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: FlutterMap(
                mapController: controller,
                options: const MapOptions(
                  initialCenter: LatLng(0, 0),
                  initialZoom: 3,
                ),
                children: const [],
              ),
            ),
          ),
          Positioned.fill(
            child: PinSemanticsLayer(
              mapController: controller,
              cards: const [card],
              stateOf: (_) => ActivityPinState.available,
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }

  /// Every semantics node carrying a tap action, with its size.
  List<SemanticsNode> tappableNodes(WidgetTester tester) {
    final out = <SemanticsNode>[];
    void visit(SemanticsNode node) {
      if (node.getSemanticsData().hasAction(SemanticsAction.tap)) {
        out.add(node);
      }
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    // The deprecated owner is the one that actually holds the test view's
    // semantics tree; rootPipelineOwner carries no SemanticsOwner in the test
    // binding, so actions sent there go nowhere.
    // ignore: deprecated_member_use
    visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    return out;
  }

  testWidgets(
    'a drawn pin is announced and activatable while the map is excluded',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = MapController();
      QuestActivityCard? opened;

      await tester.pumpWidget(
        composed(controller: controller, onTap: (c) => opened = c),
      );
      await tester.pumpAndSettle();
      // Nudge the camera so a map event re-runs the mirror's StreamBuilder
      // after the camera exists (the first build can precede map layout).
      controller.move(const LatLng(0, 0), 3);
      await tester.pumpAndSettle();

      final l10n = L10n.of(tester.element(find.byType(Stack).first));
      final label =
          'Activity: Test Activity, '
          '${ActivityPinState.available.label(l10n)}';
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Test Activity')),
      );
      expect(node.label, label);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'the mirrored pin must be activatable, not just named (#7591)',
      );

      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      expect(
        opened?.activityId,
        'a1',
        reason:
            'a screen-reader double-tap on the mirrored pin must open the '
            'activity (#7591)',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a mirrored pin is transparent to native pointer hit-testing (#7525)',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = MapController();

      await tester.pumpWidget(composed(controller: controller, onTap: (_) {}));
      await tester.pumpAndSettle();
      controller.move(const LatLng(0, 0), 3);
      await tester.pumpAndSettle();

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Test Activity')),
      );
      expect(
        node.hitTestBehavior,
        ui.SemanticsHitTestBehavior.transparent,
        reason:
            'without an explicit transparent hitTestBehavior the web engine '
            "infers pointer-events: all from the node's tap action, and the "
            'mirror captures native mouse events for anything painted over '
            "the map at the pin's position — the activity video's iframe "
            'controls went dead this way (#7525)',
      );
      semantics.dispose();
    },
  );

  testWidgets('no viewport-sized tappable node blankets the map (#8013)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = MapController();

    await tester.pumpWidget(composed(controller: controller, onTap: (_) {}));
    await tester.pumpAndSettle();
    controller.move(const LatLng(0, 0), 3);
    await tester.pumpAndSettle();

    for (final node in tappableNodes(tester)) {
      expect(
        node.rect.width < 400 || node.rect.height < 400,
        isTrue,
        reason:
            'a large tappable semantics node over the map is exactly what '
            'ExcludeSemantics exists to prevent (#8013) — the mirror must '
            'not reintroduce one: ${node.rect} "${node.label}"',
      );
    }
    semantics.dispose();
  });

  testWidgets('the mirror never intercepts pointer taps', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = MapController();
    var mirrorTapped = false;
    var mapTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: FlutterMap(
                  mapController: controller,
                  options: MapOptions(
                    initialCenter: const LatLng(0, 0),
                    initialZoom: 3,
                    onTap: (_, _) => mapTapped = true,
                  ),
                  children: const [],
                ),
              ),
            ),
            Positioned.fill(
              child: PinSemanticsLayer(
                mapController: controller,
                cards: const [card],
                stateOf: (_) => ActivityPinState.available,
                onTap: (_) => mirrorTapped = true,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.move(const LatLng(0, 0), 3);
    await tester.pumpAndSettle();

    // A pointer tap at the pin's position must fall through the mirror to the
    // map below (none of the mirror's render objects hit-test — deliberately
    // NOT IgnorePointer, which would strip the semantics tap action) — only a
    // SEMANTICS tap activates the mirror.
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    // flutter_map defers a single tap by its double-tap window; run the timer.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      mapTapped,
      isTrue,
      reason: 'the pointer tap must reach the map under the mirror',
    );
    expect(
      mirrorTapped,
      isFalse,
      reason: 'the mirror is semantics-only; pointer taps belong to the pins',
    );
    semantics.dispose();
  });

  testWidgets('a pin panned out of the viewport publishes nothing', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = MapController();

    await tester.pumpWidget(composed(controller: controller, onTap: (_) {}));
    await tester.pumpAndSettle();
    controller.move(const LatLng(0, 0), 3);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Test Activity')), findsOneWidget);

    // Fly to the antipode — the pin leaves the viewport.
    controller.move(const LatLng(0, 180), 3);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('Test Activity')),
      findsNothing,
      reason:
          'an off-viewport pin must not be announced (mirrors the marker '
          "layers' culling)",
    );
    semantics.dispose();
  });
}
