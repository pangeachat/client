import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/mobile_search_bar.dart';

/// Coverage for the single-column floating search bar
/// (routing.instructions.md → Single-column search bar): the presentational
/// contract — contextual hint, externally-owned query, the minimized compact
/// icon, and the filters slot. The scope routing (map / chats / courses) is
/// the shell's job and is covered there.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    String hintText = 'Search Pangea',
    String query = '',
    ValueChanged<String>? onQueryChanged,
    bool minimized = false,
    VoidCallback? onRestore,
    Widget? filtersChild,
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

  testWidgets('minimized renders only the compact icon; tap restores', (
    tester,
  ) async {
    var restored = false;
    await pumpBar(
      tester,
      hintText: 'Search Courses',
      minimized: true,
      onRestore: () => restored = true,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('Search Courses'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.search));
    expect(restored, isTrue);
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
}
