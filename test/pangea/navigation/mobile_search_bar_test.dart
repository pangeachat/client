import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/mobile_search_bar.dart';
import 'package:fluffychat/routes/world/world_map_empty_view_card.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';

/// Coverage for the single-column floating search bar
/// (routing.instructions.md → Single-column search bar): the presentational
/// contract — contextual hint, externally-owned query, the filters slot, and
/// the verdict-driven empty-view card with its remedy levers. The verdict
/// DIAGNOSIS lives on the controller; here the bar just renders what it is
/// told. The scope routing (map / chats / courses) is the shell's job and is
/// covered there.
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
    bool minimized = false,
    VoidCallback? onRestore,
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
              minimized: minimized,
              onRestore: onRestore,
              filtersChild: filtersChild,
              emptyVerdict: emptyVerdict,
              canZoomOut: canZoomOut,
              onWidenSearch: onWidenSearch,
              onZoomOut: onZoomOut,
              viewRevision: viewRevision,
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

  testWidgets('at the zoom floor the Zoom out lever greys out, not hides', (
    tester,
  ) async {
    var zoomedOut = false;
    await pumpBar(
      tester,
      emptyVerdict: () => MapEmptyVerdict.matchesOffscreen,
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

  testWidgets('minimized: one icon button, no field, filters or card', (
    tester,
  ) async {
    // The course-scoped resting state (#7716, routing.instructions.md →
    // Single-column search bar): the scoped map's own chrome owns the band, so
    // search waits behind one tap — and everything that rides the expanded bar
    // waits with it.
    await pumpBar(
      tester,
      minimized: true,
      filtersChild: const Text('FILTER CHIPS', key: Key('chips')),
      emptyVerdict: () => MapEmptyVerdict.matchesOffscreen,
      canZoomOut: () => true,
    );
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('chips')), findsNothing);
    expect(find.byType(WorldMapEmptyViewCard), findsNothing);
  });

  testWidgets('minimized: tapping the icon asks the shell to restore', (
    tester,
  ) async {
    var restored = false;
    await pumpBar(tester, minimized: true, onRestore: () => restored = true);
    await tester.tap(find.byIcon(Icons.search));
    expect(restored, isTrue);
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
