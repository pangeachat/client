import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/mobile_search_bar.dart';
import 'package:fluffychat/routes/world/world_map_empty_view_card.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_level_fallback_notice.dart';

/// Coverage for the single-column floating search bar
/// (routing.instructions.md → Single-column search bar): the presentational
/// contract — contextual hint, externally-owned query, the filters slot, and
/// the verdict-driven empty-view card with its remedy levers. The verdict
/// DIAGNOSIS lives on the controller; here the bar just renders what it is
/// told. The scope routing (map / chats / courses) is the shell's job and is
/// covered there — including the one scope this bar no longer has a state
/// for: under a course context the slot carries the course context bar
/// instead, which retired the bar's compact minimize (#8736).
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    String hintText = 'Search Pangea',
    String query = '',
    ValueChanged<String>? onQueryChanged,
    Widget? filtersChild,
    MapEmptyVerdict Function()? emptyVerdict,
    bool Function()? canZoomOut,
    VoidCallback? onWidenSearch,
    VoidCallback? onZoomOut,
    Listenable? viewRevision,
    WorldMapFilter Function()? filter,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MobileSearchBar(
              hintText: hintText,
              query: query,
              onQueryChanged: onQueryChanged ?? (_) {},
              filtersChild: filtersChild,
              emptyVerdict: emptyVerdict,
              canZoomOut: canZoomOut,
              onWidenSearch: onWidenSearch,
              onZoomOut: onZoomOut,
              viewRevision: viewRevision,
              filter: filter,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the scope hint and reports typing', (tester) async {
    final changes = <String>[];
    await pumpBar(tester, onQueryChanged: changes.add);
    expect(find.text('Search Pangea'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'plaza');
    expect(changes, ['plaza']);
  });

  testWidgets('an external query reset syncs into the field', (tester) async {
    await pumpBar(tester, query: 'hola');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'hola',
    );
    await pumpBar(tester, query: '');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('a non-empty query shows a clear button that empties it', (
    tester,
  ) async {
    final changes = <String>[];
    await pumpBar(tester, query: 'hola', onQueryChanged: changes.add);
    await tester.tap(find.byIcon(Icons.close));
    expect(changes, ['']);
  });

  testWidgets('the filters slot renders above the bar and only when given', (
    tester,
  ) async {
    await pumpBar(
      tester,
      filtersChild: const Text('FILTER CHIPS', key: Key('chips')),
    );
    final chipsY = tester.getTopLeft(find.byKey(const Key('chips'))).dy;
    final fieldY = tester.getTopLeft(find.byType(TextField)).dy;
    expect(
      chipsY,
      lessThan(fieldY),
      reason: 'filters ride ABOVE the search bar on narrow (the doc rule)',
    );
    await pumpBar(tester);
    expect(find.byKey(const Key('chips')), findsNothing);
  });

  testWidgets('the card rides above the bar for a verdict, none for none', (
    tester,
  ) async {
    await pumpBar(
      tester,
      emptyVerdict: () => MapEmptyVerdict.matchesOffscreen,
      canZoomOut: () => true,
    );
    expect(find.byType(WorldMapEmptyViewCard), findsOneWidget);
    final cardY = tester.getTopLeft(find.byType(WorldMapEmptyViewCard)).dy;
    final fieldY = tester.getTopLeft(find.byType(TextField)).dy;
    expect(cardY, lessThan(fieldY));

    await pumpBar(tester, emptyVerdict: () => MapEmptyVerdict.none);
    expect(find.byType(WorldMapEmptyViewCard), findsNothing);
  });

  testWidgets('a level fallback rides above the bar and names both levels', (
    tester,
  ) async {
    const fallback = WorldMapFilter(
      cefrFilter: {LanguageLevelTypeEnum.preA1},
      cefrFallback: LanguageLevelTypeEnum.a1,
    );
    await pumpBar(
      tester,
      emptyVerdict: () => MapEmptyVerdict.none,
      filter: () => fallback,
    );
    expect(find.byType(WorldMapLevelFallbackNotice), findsOneWidget);
    final noticeY = tester
        .getTopLeft(find.byType(WorldMapLevelFallbackNotice))
        .dy;
    expect(noticeY, lessThan(tester.getTopLeft(find.byType(TextField)).dy));

    // An honoured level says nothing.
    await pumpBar(
      tester,
      emptyVerdict: () => MapEmptyVerdict.none,
      filter: () =>
          const WorldMapFilter(cefrFilter: {LanguageLevelTypeEnum.a1}),
    );
    expect(find.byType(WorldMapLevelFallbackNotice), findsNothing);
  });

  testWidgets('the empty-view card outranks the fallback notice', (
    tester,
  ) async {
    await pumpBar(
      tester,
      emptyVerdict: () => MapEmptyVerdict.filtersHideMatches,
      filter: () => const WorldMapFilter(
        cefrFilter: {LanguageLevelTypeEnum.preA1},
        cefrFallback: LanguageLevelTypeEnum.a1,
      ),
    );
    expect(find.byType(WorldMapEmptyViewCard), findsOneWidget);
    expect(
      find.byType(WorldMapLevelFallbackNotice),
      findsNothing,
      reason: 'a map with nothing on it is the more urgent message',
    );
  });

  testWidgets('off-screen matches: Zoom out fires, no Widen offered', (
    tester,
  ) async {
    var zoomedOut = false;
    await pumpBar(
      tester,
      emptyVerdict: () => MapEmptyVerdict.matchesOffscreen,
      canZoomOut: () => true,
      onZoomOut: () => zoomedOut = true,
    );
    expect(find.textContaining('outside your view'), findsOneWidget);
    await tester.tap(find.text('Zoom out'));
    expect(zoomedOut, isTrue);
    expect(find.text('Widen search'), findsNothing);
  });

  testWidgets('off-screen matches keep the lever live at the zoom floor', (
    tester,
  ) async {
    // #8121: the lever re-centers as well as zooms, and a narrow screen at the
    // floor still can't show the whole world — so matches loaded off-screen
    // are exactly when it must stay pressable, not grey out.
    var zoomedOut = false;
    await pumpBar(
      tester,
      emptyVerdict: () => MapEmptyVerdict.matchesOffscreen,
      canZoomOut: () => false,
      onZoomOut: () => zoomedOut = true,
    );
    await tester.tap(find.text('Zoom out'));
    expect(zoomedOut, isTrue);
  });

  testWidgets('an empty area greys the lever out at the floor, not hides', (
    tester,
  ) async {
    var zoomedOut = false;
    await pumpBar(
      tester,
      emptyVerdict: () => MapEmptyVerdict.noActivities,
      canZoomOut: () => false,
      onZoomOut: () => zoomedOut = true,
    );
    // bySubtype, not byType: FilledButton.tonalIcon builds a private
    // FilledButton SUBCLASS, which exact-type matching misses.
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Zoom out'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );
    expect(button.onPressed, isNull, reason: 'disabled at the floor');
    await tester.tap(find.text('Zoom out'), warnIfMissed: false);
    expect(zoomedOut, isFalse);
  });

  testWidgets('pill-excluded matches: Widen search fires, no Zoom out', (
    tester,
  ) async {
    var widened = false;
    await pumpBar(
      tester,
      emptyVerdict: () => MapEmptyVerdict.filtersHideMatches,
      canZoomOut: () => true,
      onWidenSearch: () => widened = true,
    );
    expect(find.textContaining('filters are hiding'), findsOneWidget);
    await tester.tap(find.text('Widen search'));
    expect(widened, isTrue);
    expect(find.text('Zoom out'), findsNothing);
  });

  testWidgets('a dead query offers no levers at all', (tester) async {
    await pumpBar(
      tester,
      emptyVerdict: () => MapEmptyVerdict.noSearchMatches,
      canZoomOut: () => true,
    );
    expect(find.textContaining('match your search'), findsOneWidget);
    expect(find.bySubtype<FilledButton>(), findsNothing);
  });

  testWidgets('an empty area offers Zoom out', (tester) async {
    await pumpBar(
      tester,
      emptyVerdict: () => MapEmptyVerdict.noActivities,
      canZoomOut: () => true,
    );
    expect(find.textContaining('in this area'), findsOneWidget);
    expect(find.text('Zoom out'), findsOneWidget);
  });

  testWidgets('a viewRevision tick re-reads the live verdict', (tester) async {
    // Mimics the real flow: the verdict flips via a filter pill / pin load —
    // changes that never rebuild this shell-built bar — and the controller's
    // tick is what surfaces the card.
    var verdict = MapEmptyVerdict.none;
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    await pumpBar(
      tester,
      emptyVerdict: () => verdict,
      canZoomOut: () => true,
      viewRevision: revision,
    );
    expect(find.byType(WorldMapEmptyViewCard), findsNothing);

    verdict = MapEmptyVerdict.matchesOffscreen;
    revision.value++;
    await tester.pumpAndSettle();
    expect(find.byType(WorldMapEmptyViewCard), findsOneWidget);
  });
}
