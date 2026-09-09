import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_entry_intent.dart';
import 'package:fluffychat/routes/world/right_panel/panel_entry_focus.dart';

/// A panel opened from the user cluster lands focus on the panel's own named
/// group a discrete beat after it mounts — announced by page name, not a Tab
/// stop, the next Tab reaching its first control; a panel opened any other
/// way, or from a stale press, leaves focus where it was
/// (routing.instructions.md, "Every panel is a named group to assistive tech").
void main() {
  late DateTime now;
  late PanelEntryIntent intent;
  late FocusNode cluster;
  late FocusNode close;
  late FocusNode practice;

  setUp(() {
    now = DateTime(2026, 9, 9, 12);
    intent = PanelEntryIntent.forTest(now: () => now);
    cluster = FocusNode(debugLabel: 'cluster');
    close = FocusNode(debugLabel: 'close');
    practice = FocusNode(debugLabel: 'practice');
  });
  tearDown(() {
    cluster.dispose();
    close.dispose();
    practice.dispose();
  });

  // The shell's shape: an ordered workspace group, the cluster ranked after
  // the right panels, the panel in its own ordered group.
  Widget host({required bool panelOpen}) => MaterialApp(
    home: FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Scaffold(
        body: Column(
          children: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: ElevatedButton(
                focusNode: cluster,
                onPressed: () {},
                child: const Text('Vocab'),
              ),
            ),
            if (panelOpen)
              FocusTraversalOrder(
                order: const NumericFocusOrder(3),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: PanelEntryFocus(
                    label: 'Vocab page',
                    sortKey: const OrdinalSortKey(3),
                    intent: intent,
                    child: Column(
                      children: [
                        IconButton(
                          focusNode: close,
                          tooltip: 'Close Vocab',
                          icon: const Icon(Icons.close),
                          onPressed: () {},
                        ),
                        TextButton(
                          focusNode: practice,
                          onPressed: () {},
                          child: const Text('Practice'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  /// Whether the panel's named group is the node assistive tech is on.
  bool groupFocused(WidgetTester tester) =>
      tester.semantics.simulatedAccessibilityTraversal().any(
        (n) =>
            n.getSemanticsData().label == 'Vocab page' &&
            n.flagsCollection.isFocused == Tristate.isTrue,
      );

  Future<void> openFromCluster(WidgetTester tester) async {
    await tester.pumpWidget(host(panelOpen: false));
    cluster.requestFocus();
    await tester.pump();
    expect(cluster.hasPrimaryFocus, isTrue);
  }

  testWidgets(
    'an armed open lands focus on the panel group, Tab on its first control',
    (tester) async {
      final handle = tester.ensureSemantics();
      await openFromCluster(tester);
      intent.arm();
      await tester.pumpWidget(host(panelOpen: true));
      await tester.pump();
      expect(
        cluster.hasPrimaryFocus,
        isTrue,
        reason: 'one discrete beat later',
      );
      await tester.pump(PanelEntryFocus.claimDelay);
      expect(cluster.hasPrimaryFocus, isFalse);
      expect(
        close.hasPrimaryFocus,
        isFalse,
        reason: 'the group, not its control',
      );
      expect(
        groupFocused(tester),
        isTrue,
        reason: 'assistive tech is on the page',
      );

      // The group is not a Tab stop: Tab reaches the panel's first control,
      // then moves on inside it.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(close.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(practice.hasPrimaryFocus, isTrue);
      handle.dispose();
    },
  );

  testWidgets('an open without the intent leaves focus where it was', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await openFromCluster(tester);
    await tester.pumpWidget(host(panelOpen: true));
    await tester.pump(PanelEntryFocus.claimDelay);
    expect(cluster.hasPrimaryFocus, isTrue);
    expect(groupFocused(tester), isFalse);
    handle.dispose();
  });

  testWidgets('a stale arm is ignored', (tester) async {
    await openFromCluster(tester);
    intent.arm();
    now = now.add(PanelEntryIntent.ttl + const Duration(seconds: 1));
    await tester.pumpWidget(host(panelOpen: true));
    await tester.pump(PanelEntryFocus.claimDelay);
    expect(cluster.hasPrimaryFocus, isTrue);
  });

  testWidgets('an arm is consumed once', (tester) async {
    await openFromCluster(tester);
    intent.arm();
    await tester.pumpWidget(host(panelOpen: true));
    await tester.pump(PanelEntryFocus.claimDelay);
    expect(cluster.hasPrimaryFocus, isFalse);
    expect(intent.take(), isFalse);
  });
}
