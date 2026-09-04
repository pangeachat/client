import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics_data/analytics_updater_mixin.dart';
import 'package:fluffychat/features/overlay/any_state_holder.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/gain_points_animation.dart';
import 'package:fluffychat/routes/chat/growth_animation.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// #8613 — XP/growth celebrations are hosted in the Overlay nearest their
/// anchor, resolved from the anchor registry, never from the context of
/// whichever listener happened to hear the update. A listener in one panel
/// (an open chat) hears XP earned in another (the vocab page); an overlay
/// resolved from the listener's context lives in its nested Navigator, where
/// the other panel's anchor never paints.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const targetId = 'celebration_anchor_test';
  final nestedOverlayKey = GlobalKey(debugLabel: 'nested_overlay');

  setUp(() {
    // The registry is a global static; give every test a clean one.
    MatrixState.pAnyState = PangeaAnyState();
  });

  /// An app whose anchor lives inside its own nested [Overlay] — the shape of
  /// a workspace panel — so the test can tell the anchor's overlay apart from
  /// the root one.
  Future<void> pumpAnchoredApp(WidgetTester tester) async {
    final linkAndKey = MatrixState.pAnyState.layerLinkAndKey(targetId);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Overlay(
            key: nestedOverlayKey,
            initialEntries: [
              OverlayEntry(
                builder: (_) => Center(
                  child: CompositedTransformTarget(
                    link: linkAndKey.link,
                    child: SizedBox(key: linkAndKey.key, width: 24, height: 24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('XP burst renders in the overlay nearest the anchor', (
    tester,
  ) async {
    await pumpAnchoredApp(tester);

    PointsGainedAnimation.show(targetId, 3);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(nestedOverlayKey),
        matching: find.byType(PointsGainedAnimation),
      ),
      findsOneWidget,
    );

    // Run the animation out so it closes its own overlay entry.
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();
    expect(find.byType(PointsGainedAnimation), findsNothing);
  });

  testWidgets('growth animation renders in the overlay nearest the anchor', (
    tester,
  ) async {
    await pumpAnchoredApp(tester);

    GrowthAnimation.show(
      targetId,
      '${targetId}_growth',
      const Icon(Icons.eco, size: 24),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(nestedOverlayKey),
        matching: find.byType(GrowthAnimation),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump();
    expect(find.byType(GrowthAnimation), findsNothing);
  });

  testWidgets('celebrations no-op when the anchor is not mounted', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    PointsGainedAnimation.show(targetId, 3);
    GrowthAnimation.show(
      targetId,
      '${targetId}_growth',
      const Icon(Icons.eco, size: 24),
    );
    await tester.pump();

    expect(find.byType(PointsGainedAnimation), findsNothing);
    expect(find.byType(GrowthAnimation), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('XP-earning surfaces outside chat host the celebration listeners', () {
    // #8613 regression pin: these pages record construct uses with a targetId
    // (emoji picks on the vocab page, collectable chips on the activity start
    // page) but sat outside every AnalyticsUpdater host, so the XP was
    // recorded silently. The typed tear-off list stops COMPILING if a refactor
    // drops the mixin — caught here instead of in user testing.
    final List<AnalyticsUpdater Function()> hosts = [
      ConstructAnalyticsViewState.new,
      ActivitySessionStartState.new,
    ];
    expect(hosts, hasLength(2));
  });
}
