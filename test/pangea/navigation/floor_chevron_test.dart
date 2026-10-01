import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/left_panel/floor_chevron.dart';
import 'package:fluffychat/widgets/layouts/cavity_controls.dart';

/// The course panel's one control (#8816). Its floor differs by form factor —
/// the nav cavity's peek on narrow, the context bar on wide — but the control
/// must be the same chevron in the same place either way, which is exactly
/// what these pin.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );

  /// The chevron's rotation is the only thing saying which way it goes, so the
  /// assertions read it rather than trusting the flag that set it.
  double turnsOf(WidgetTester tester) =>
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns;

  group('in a cavity (narrow)', () {
    testWidgets('drives the cavity and rotates with its state', (tester) async {
      var toggles = 0;
      final expanded = ValueNotifier<bool>(false);
      addTearDown(expanded.dispose);

      await pump(
        tester,
        CavityControls(
          expandToFull: () {},
          toggleCollapse: () => toggles++,
          expanded: expanded,
          child: const FloorChevron(),
        ),
      );

      // The sheet SLIDES, so the chevron points the way it will travel: at
      // the floor it points UP, where the sheet is about to go.
      expect(turnsOf(tester), 0.5);
      await tester.tap(find.byType(IconButton));
      expect(toggles, 1);

      expanded.value = true;
      await tester.pumpAndSettle();
      // Expanded it points DOWN, the way a collapse would travel.
      expect(turnsOf(tester), 0.0);
    });
  });

  group('off cavity (wide)', () {
    testWidgets('collapses via the fallback, pointing UP', (tester) async {
      var collapses = 0;
      await pump(tester, FloorChevron(onToggleOffCavity: () => collapses++));

      // Nothing slides on wide — the panel appears in place — so the chevron
      // follows the DISCLOSURE convention, the inverse of the sheet's: open,
      // it points up to say the tap hides what is showing.
      expect(turnsOf(tester), 0.5);
      await tester.tap(find.byType(IconButton));
      expect(collapses, 1);
    });

    testWidgets('the bar, its collapsed twin, points DOWN to reveal', (
      tester,
    ) async {
      await pump(
        tester,
        ChevronToggle(
          expanded: false,
          onTap: () {},
          meaning: ChevronMeaning.disclosure,
        ),
      );
      expect(turnsOf(tester), 0.0);
    });

    testWidgets('the two conventions are exact inverses', (tester) async {
      for (final expanded in [true, false]) {
        await pump(
          tester,
          ChevronToggle(
            expanded: expanded,
            onTap: () {},
            meaning: ChevronMeaning.motion,
          ),
        );
        final motion = turnsOf(tester);
        await pump(
          tester,
          ChevronToggle(
            expanded: expanded,
            onTap: () {},
            meaning: ChevronMeaning.disclosure,
          ),
        );
        expect(turnsOf(tester), (motion + 0.5) % 1.0);
      }
    });

    testWidgets('renders nothing with no cavity and no fallback', (
      tester,
    ) async {
      await pump(tester, const FloorChevron());
      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('the expanded state rides the chevron\'s own button node', () {
    // Every host draws the chevron inside a named group of its own — the
    // course card's "Course details page", the cavity's panel. A bare
    // `Semantics` is not a boundary, so its flag merges UP into that group
    // and the screen reader announces the state on the page while the
    // control the learner is actually on announces none.
    const hostKey = Key('host group');

    Future<void> pumpInHost(WidgetTester tester, Widget chevron) => pump(
      tester,
      Semantics(
        key: hostKey,
        container: true,
        label: 'Course details page',
        child: chevron,
      ),
    );

    SemanticsNode buttonNode(WidgetTester tester) =>
        tester.getSemantics(find.byType(IconButton));
    SemanticsNode hostNode(WidgetTester tester) =>
        tester.getSemantics(find.byKey(hostKey));

    testWidgets('the button carries it, in both states', (tester) async {
      final semantics = tester.ensureSemantics();

      await pumpInHost(
        tester,
        ChevronToggle(
          expanded: true,
          onTap: () {},
          meaning: ChevronMeaning.motion,
        ),
      );
      // One node, the button's own: it announces what it is AND what state
      // it is in — no extra node between the learner and the control.
      expect(buttonNode(tester).flagsCollection.isButton, isTrue);
      expect(buttonNode(tester).flagsCollection.isExpanded, Tristate.isTrue);
      // ...and the group around it announces no state of its own.
      expect(hostNode(tester).flagsCollection.isExpanded, Tristate.none);

      await pumpInHost(
        tester,
        ChevronToggle(
          expanded: false,
          onTap: () {},
          meaning: ChevronMeaning.motion,
        ),
      );
      expect(buttonNode(tester).flagsCollection.isExpanded, Tristate.isFalse);
      expect(hostNode(tester).flagsCollection.isExpanded, Tristate.none);
      semantics.dispose();
    });
  });
}
