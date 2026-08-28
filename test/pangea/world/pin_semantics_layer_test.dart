import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/dot_markers_layer.dart';
import 'package:fluffychat/routes/world/large_markers_layer.dart';
import 'package:fluffychat/routes/world/pin_semantics_layer.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';
import 'package:fluffychat/routes/world/world_map_view.dart';

/// Covers #7591 at the COMPOSED level — the level the standalone pin tests in
/// world_map_semantics_activation_test.dart cannot see. The map subtree is
/// ExcludeSemantics'd (#8013, permanent — upstream declined the fix in
/// fleaflet/flutter_map#2236), which drops the pins' own semantics; the
/// [PinSemanticsLayer] mirror re-authors them outside the excluded subtree.
/// These tests pump the same composition the view builds (excluded FlutterMap
/// below, mirror above) and assert the contract: pins are announced and
/// activatable through semantics, **each mirror node's rect is its drawn
/// marker's rect** (so a screen reader's focus highlight traces the visible
/// pin), and no viewport-sized tappable node exists to blanket DOM embeds.
void main() {
  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Test Activity',
    l2: 'es',
    // [longitude, latitude] — dead center of the initial camera below.
    coordinates: [0, 0],
    learningObjectiveRefs: [],
  );

  // The same geometry resolvers on both sides (drawn layer and mirror), as
  // the view wires them — the mid teardrop's tip-at-anchor alignment included,
  // so the drift test exercises a non-center anchor.
  Size markerBox(ActivityPinState state, PinTier tier) => tier.markerBox(state);
  Alignment markerAlignment(ActivityPinState state, PinTier tier) {
    if (tier != PinTier.mid || state == ActivityPinState.inProgress) {
      return Alignment.center;
    }
    final tipY = PinSize.midDiameter + PinSize.midPointHeight;
    return Marker.computePixelAlignment(
      width: PinSize.midDiameter,
      height: tipY,
      left: PinSize.midDiameter / 2,
      top: tipY,
    );
  }

  Widget composed({
    required MapController controller,
    required void Function(QuestActivityCard) onTap,
    List<Widget> mapChildren = const [],
    List<QuestActivityCard> cards = const [card],
    PinTier Function(String)? tierOf,
    void Function(TapPosition, LatLng)? onMapTap,
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
                options: MapOptions(
                  initialCenter: const LatLng(0, 0),
                  initialZoom: 3,
                  onTap: onMapTap,
                ),
                children: mapChildren,
              ),
            ),
          ),
          Positioned.fill(
            child: PinSemanticsLayer(
              mapController: controller,
              cards: cards,
              stateOf: (_) => ActivityPinState.available,
              tierOf: tierOf ?? (_) => PinTier.small,
              markerBox: markerBox,
              markerAlignment: markerAlignment,
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

  /// The mirror node for [title]'s pin, found as a WIDGET so [WidgetTester]
  /// reports its global rect directly. Scoped under [PinSemanticsLayer] to
  /// tell it apart from the real pin's own (semantics-excluded) widget, which
  /// shares the label.
  Finder mirrorNode(String title) => find.descendant(
    of: find.byType(PinSemanticsLayer),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label ?? '').startsWith('Activity: $title'),
    ),
  );

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

  testWidgets('mirror rects coincide with the drawn markers at every tier', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = MapController();

    const dotCard = QuestActivityCard(
      activityId: 'small',
      title: 'Small Pin',
      l2: 'es',
      coordinates: [-30.0, -20.0],
      learningObjectiveRefs: [],
    );
    const midCard = QuestActivityCard(
      activityId: 'mid',
      title: 'Mid Pin',
      l2: 'es',
      coordinates: [30.0, 20.0],
      learningObjectiveRefs: [],
    );
    const largeCard = QuestActivityCard(
      activityId: 'large',
      title: 'Large Card',
      l2: 'es',
      coordinates: [0.0, 0.0],
      learningObjectiveRefs: [],
    );
    const tiers = {
      'small': PinTier.small,
      'mid': PinTier.mid,
      'large': PinTier.large,
    };
    PinTier tierOf(String id) => tiers[id]!;

    final dotLayer = DotMarkersLayer(
      nonLargeCards: const [dotCard, midCard],
      tierOf: tierOf,
      stateOf: (_) => ActivityPinState.available,
      starLevelOf: (_) => ActivityStarLevel.none,
      nonStartableOf: (_) => false,
      pingedOf: (_) => false,
      activeActivityInstance: null,
      markerBox: markerBox,
      markerAlignment: markerAlignment,
      focusedId: null,
      onTap: (_) {},
      animateInOf: (_) => false,
      sessionParticipants: (_, _) => (participants: const [], openSlots: 0),
    ).layer();
    final largeLayer = LargeMarkersLayer(
      largeCards: const [largeCard],
      currentLarge: const {
        'large': LargeCardSnapshot(
          card: largeCard,
          state: ActivityPinState.available,
          pinged: false,
          plan: null,
          liveRoom: null,
          starsEarned: 0,
          participants: [],
          openSlots: 0,
          starLevel: ActivityStarLevel.none,
        ),
      },
      focusedId: null,
      onTap: (_) {},
      onClose: (_) {},
      animateInOf: (_) => false,
    ).layer();

    await tester.pumpWidget(
      composed(
        controller: controller,
        onTap: (_) {},
        mapChildren: [dotLayer, largeLayer],
        cards: const [largeCard, dotCard, midCard],
        tierOf: tierOf,
      ),
    );
    await tester.pumpAndSettle();
    controller.move(const LatLng(0, 0), 3);
    await tester.pumpAndSettle();

    Rect drawnRect(String id) {
      if (id == 'large') {
        // The large marker's direct child: the Align keyed by activity id,
        // sized to the whole marker box.
        return tester.getRect(find.byKey(const ValueKey('large')));
      }
      return tester.getRect(
        find.byWidgetPredicate(
          (w) => w is WorldMapDot && w.card.activityId == id,
        ),
      );
    }

    for (final entry in {
      'small': 'Small Pin',
      'mid': 'Mid Pin',
      'large': 'Large Card',
    }.entries) {
      final drawn = drawnRect(entry.key);
      final mirrored = tester.getRect(mirrorNode(entry.value));
      expect(
        mirrored,
        rectMoreOrLessEquals(drawn, epsilon: 0.01),
        reason:
            "the ${entry.key} pin's mirror node must occupy exactly the "
            "drawn marker's rect, so a screen reader's focus highlight "
            'traces the visible pin (#7591)',
      );
    }
    semantics.dispose();
  });

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
      composed(
        controller: controller,
        onTap: (_) => mirrorTapped = true,
        onMapTap: (_, _) => mapTapped = true,
      ),
    );
    await tester.pumpAndSettle();
    controller.move(const LatLng(0, 0), 3);
    await tester.pumpAndSettle();

    // A pointer tap at the pin's position must fall through the mirror to the
    // map below — only a SEMANTICS tap activates the mirror.
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
