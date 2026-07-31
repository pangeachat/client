import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_filter_bar.dart';
import 'package:fluffychat/routes/world/world_map_mobile_filters.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// Coverage for the single-column collapsible filter surface: collapsed by
/// default to a filter button with a count badge (how many categories are off
/// "All"), expanding to the full [WorldMapFilterBar] on tap and folding back on
/// a map pan (the collapse signal) or the toggle. The pill wiring itself is
/// [WorldMapFilterBar]'s contract, covered separately.
void main() {
  // The widget reads the filter live via filterBuilder, so tests mutate this to
  // mimic the controller replacing its filter object on each change.
  late WorldMapFilter filter;

  // Stand-in for WorldMapController.mapPanTick: incrementing it is a "pan".
  late ValueNotifier<int> pan;

  // Stand-in for WorldMapController.viewRevision: incrementing it signals a
  // filter change from OUTSIDE this bar (widen / reset / settings).
  late ValueNotifier<int> revision;

  setUp(() {
    filter = const WorldMapFilter();
    pan = ValueNotifier(0);
    revision = ValueNotifier(0);
  });

  tearDown(() {
    pan.dispose();
    revision.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: WorldMapMobileFilters(
              filterBuilder: () => filter,
              onSetLevel: (_) {},
              onSetPartySize: (_) {},
              onSetStatus: (_) {},
              onReset: () {},
              collapseSignal: pan,
              filterRevision: revision,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts collapsed: the button shows, the pill bar does not', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byTooltip('Show filters'), findsOneWidget);
    expect(find.byType(WorldMapFilterBar), findsNothing);
  });

  testWidgets('the badge counts categories off "All" (query excluded)', (
    tester,
  ) async {
    // Level (one CEFR level) + status set = 2; the query is not a category.
    filter = const WorldMapFilter(
      query: 'plaza',
      cefrFilter: {LanguageLevelTypeEnum.b1},
      status: ActivityPinState.available,
    );
    await pump(tester);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('no badge when every category is at "All"', (tester) async {
    await pump(tester); // default filter: empty level, null party, null status
    expect(find.text('0'), findsNothing);
  });

  testWidgets(
    'an external filter change (widen) refreshes the badge on a revision tick',
    (tester) async {
      filter = const WorldMapFilter(
        cefrFilter: {LanguageLevelTypeEnum.b1},
        status: ActivityPinState.available,
      );
      await pump(tester);
      expect(find.text('2'), findsOneWidget);

      // Widen clears every pill on the controller (which this bar does not
      // build), then ticks viewRevision — the bar must re-read and drop to 0.
      filter = const WorldMapFilter();
      revision.value++;
      await tester.pumpAndSettle();
      expect(find.text('2'), findsNothing);
      expect(find.text('0'), findsNothing); // no badge at all when all "All"
    },
  );

  testWidgets('tapping the button expands to the full pill bar', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Show filters'));
    await tester.pumpAndSettle();
    expect(find.byType(WorldMapFilterBar), findsOneWidget);
    expect(find.byTooltip('Hide filters'), findsOneWidget);
  });

  testWidgets('a map pan collapses an expanded bar back to the button', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Show filters'));
    await tester.pumpAndSettle();
    expect(find.byType(WorldMapFilterBar), findsOneWidget);

    pan.value++; // the learner pans the map
    await tester.pumpAndSettle();
    expect(find.byType(WorldMapFilterBar), findsNothing);
    expect(find.byTooltip('Show filters'), findsOneWidget);
  });

  testWidgets('the toggle collapses the bar without a pan', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Show filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hide filters'));
    await tester.pumpAndSettle();
    expect(find.byType(WorldMapFilterBar), findsNothing);
    expect(find.byTooltip('Show filters'), findsOneWidget);
  });
}
