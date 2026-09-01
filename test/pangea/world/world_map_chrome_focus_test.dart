import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/world/pin_semantics_layer.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_filter_bar.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';

/// Covers #8724 (finding 4 of the 2026-09 a11y triage, #8689): keyboard focus
/// on the world map chrome must always be VISIBLE. The filter pills are
/// PopupMenuButtons whose opaque pill fill swallows InkWell's behind-the-child
/// focus highlight (the #7219 failure mode — measured at exactly 0 changed
/// pixels on staging), so they draw the app's gold focus ring explicitly. The
/// composed walk then proves the whole chrome ring: Tab moves pin layer →
/// search field → each pill → the on-map controls with no invisible stop in
/// between — the map subtree is ExcludeSemantics'd (#8013), which hides
/// widgets from AT but NOT from Tab order, so any focusable inside it without
/// ExcludeFocus is an invisible dead stop (2.4.7).
void main() {
  // Rings render only in traditional (keyboard) highlight mode; the test
  // binding's platform defaults to touch, so pin the mode for the ring
  // assertions. The touch-gate test below overrides it per-test.
  setUp(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDownAll(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  /// The gold focus ring: the [FocusRingTapTarget.ringWidth]-side
  /// ShapeDecoration drawn while focused (same assertion as
  /// cluster_keyboard_focus_test — one shared ring look).
  Finder goldRing() => find.byWidgetPredicate(
    (w) =>
        w is DecoratedBox &&
        w.decoration is ShapeDecoration &&
        (w.decoration as ShapeDecoration).shape is OutlinedBorder &&
        ((w.decoration as ShapeDecoration).shape as OutlinedBorder)
                .side
                .width ==
            FocusRingTapTarget.ringWidth,
  );

  /// The pill label the (single) current gold ring encloses — which control
  /// the visible focus indicator is actually on.
  void expectRingOn(WidgetTester tester, String label) {
    expect(
      goldRing(),
      findsOneWidget,
      reason:
          'exactly one control wears the focus ring at a time; focus is on '
          '${FocusManager.instance.primaryFocus}',
    );
    expect(
      find.descendant(of: goldRing(), matching: find.text(label)),
      findsOneWidget,
      reason:
          'the ring must be on "$label"; focus is on '
          '${FocusManager.instance.primaryFocus}',
    );
  }

  Widget filterBar({VoidCallback? onReset, WorldMapFilter? filter}) {
    return MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: WorldMapFilterBar(
            filter: filter ?? const WorldMapFilter(),
            onSetLevel: (_) {},
            onSetPartySize: (_) {},
            onSetStatus: (_) {},
            onReset: onReset ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Tab reaches each filter pill with a visible gold ring; Enter opens the '
    'dropdown',
    (tester) async {
      await tester.pumpWidget(filterBar());
      await tester.pumpAndSettle();
      final l10n = L10n.of(tester.element(find.byType(WorldMapFilterBar)));

      expect(goldRing(), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expectRingOn(tester, l10n.mapFilterAllLevels);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expectRingOn(tester, l10n.mapFilterAllPlayers);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expectRingOn(tester, l10n.mapFilterAllStatuses);

      // Enter opens the focused pill's dropdown (keyboard operability, not
      // just reachability): the menu adds a second "All statuses" — the
      // leading option row above the status values.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.mapFilterAllStatuses),
        findsNWidgets(2),
        reason: 'Enter on a focused pill must open its dropdown',
      );
      expect(find.text(l10n.mapStatusOpenToJoin), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text(l10n.mapStatusOpenToJoin), findsNothing);
    },
  );

  testWidgets('no ring in touch highlight mode — a keyboard affordance only', (
    tester,
  ) async {
    // The Material focus-highlight gate (#8724 review): touch interaction
    // must never paint the explicit rings.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await tester.pumpWidget(filterBar());
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      goldRing(),
      findsNothing,
      reason:
          'focus rings are keyboard affordances; in touch highlight mode '
          'they must not render',
    );
  });

  testWidgets('the ring follows focus off a pill instead of sticking', (
    tester,
  ) async {
    await tester.pumpWidget(filterBar());
    await tester.pumpAndSettle();
    final l10n = L10n.of(tester.element(find.byType(WorldMapFilterBar)));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expectRingOn(tester, l10n.mapFilterAllLevels);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: goldRing(),
        matching: find.text(l10n.mapFilterAllLevels),
      ),
      findsNothing,
      reason: 'the Level pill must drop its ring once focus moves on',
    );
  });

  // The user-visible chrome contract (#8724, extending #8714's probe): Tab
  // walks the map's REAL chrome — pin layer → search field → the three filter
  // pills → the on-map controls — landing every press on a control with a
  // visible indicator, never on an invisible focusable inside the
  // ExcludeSemantics'd map subtree. Pumps the view's actual composition
  // (large card with its dismiss X, attribution widget, real search overlay)
  // so a focusable added to the map subtree without ExcludeFocus fails here.
  testWidgets('Tab walks the composed chrome with no invisible dead stop', (
    tester,
  ) async {
    const card = QuestActivityCard(
      activityId: 'a1',
      title: 'Test Activity',
      l2: 'es',
      // [longitude, latitude] — dead center of the initial camera.
      coordinates: [0, 0],
      learningObjectiveRefs: [],
    );
    final semantics = tester.ensureSemantics();
    final controller = MapController();
    // Mirror the view's #7219 config: the map's own invisible focus target
    // stays out of Tab traversal and never autofocuses.
    final mapFocusNode = FocusNode(
      debugLabel: 'FlutterMap',
      skipTraversal: true,
    );
    final zoomFocusNode = FocusNode(debugLabel: 'ZoomControlStandIn');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: FlutterMap(
                    mapController: controller,
                    options: MapOptions(
                      initialCenter: const LatLng(0, 0),
                      initialZoom: 3,
                      interactionOptions: InteractionOptions(
                        keyboardOptions: KeyboardOptions(
                          focusNode: mapFocusNode,
                          autofocus: false,
                        ),
                      ),
                    ),
                    children: [
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: const LatLng(10, 40),
                            width: 260,
                            height: 180,
                            child: WorldMapLargeCard(
                              card: card,
                              state: ActivityPinState.available,
                              pinged: false,
                              plan: null,
                              starsEarned: 0,
                              participants: const [],
                              openSlots: 0,
                              onTap: () {},
                              onClose: () {},
                            ),
                          ),
                        ],
                      ),
                      // The view wraps the attribution in ExcludeFocus — its
                      // internal expand IconButton is otherwise an invisible
                      // Tab stop (#8714).
                      ExcludeFocus(
                        child: RichAttributionWidget(
                          alignment: AttributionAlignment.bottomLeft,
                          attributions: [
                            TextSourceAttribution(
                              'OpenStreetMap contributors',
                              onTap: () {},
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: PinSemanticsLayer(
                  mapController: controller,
                  cards: const [card],
                  stateOf: (_) => ActivityPinState.available,
                  onTap: (_) {},
                ),
              ),
              // The real search + filter overlay, at the view's spot.
              Positioned(
                top: 12,
                left: 12,
                width: 360,
                child: WorldMapSearchOverlay(
                  filter: const WorldMapFilter(),
                  updateQuery: (_) {},
                  onWidenSearch: () {},
                  setCefrLevel: (_) {},
                  setPartySize: (_) {},
                  setStatus: (_) {},
                  results: const [],
                  onResultTap: (_) {},
                  onReset: () {},
                  emptyVerdict: MapEmptyVerdict.none,
                  canZoomOut: true,
                  onZoomOut: () {},
                ),
              ),
              // Stand-in for the bottom-right zoom controls (the real ones
              // need the full WorldMapController): the next focusable after
              // the pills in reading order, so the walk proves Tab leaves
              // the overlay onto the on-map controls in ONE press.
              Positioned(
                right: 12,
                bottom: 28,
                child: IconButton(
                  focusNode: zoomFocusNode,
                  icon: const Icon(Icons.public),
                  tooltip: 'Zoom stand-in',
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Nudge the camera so a map event re-runs the mirror's StreamBuilder
    // after the camera exists (the first build can precede map layout).
    controller.move(const LatLng(0, 0), 3);
    await tester.pumpAndSettle();
    final l10n = L10n.of(tester.element(find.byType(WorldMapFilterBar)));

    // Tab 1: the pin layer (its authored roving ring — #8714).
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      find.byKey(PinSemanticsLayerState.ringKey),
      findsOneWidget,
      reason:
          'Tab 1 must rove the pin layer; focus landed on '
          '${FocusManager.instance.primaryFocus}',
    );

    // Tab 2: the search field.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(
      editable.focusNode.hasFocus,
      isTrue,
      reason:
          'Tab 2 must reach the search field; focus landed on '
          '${FocusManager.instance.primaryFocus} — an invisible dead stop '
          'in between (2.4.7)',
    );

    // Tabs 3–5: the three pills, each wearing the visible ring.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expectRingOn(tester, l10n.mapFilterAllLevels);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expectRingOn(tester, l10n.mapFilterAllPlayers);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expectRingOn(tester, l10n.mapFilterAllStatuses);

    // Tab 6: straight onto the on-map controls — nothing invisible between
    // the last pill and the next real control (the pre-#8717 staging
    // measurement found 3 consecutive dead presses exactly here: the large
    // cards' un-excluded dismiss X's).
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      zoomFocusNode.hasFocus,
      isTrue,
      reason:
          'one Tab from the last pill must reach the next real control; '
          'focus landed on ${FocusManager.instance.primaryFocus} instead — '
          'an invisible dead stop in the map subtree (2.4.7, #8724)',
    );

    mapFocusNode.dispose();
    zoomFocusNode.dispose();
    semantics.dispose();
  });
}
