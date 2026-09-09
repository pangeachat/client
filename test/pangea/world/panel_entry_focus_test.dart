import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_entry_intent.dart';
import 'package:fluffychat/routes/world/right_panel/panel_entry_focus.dart';

/// A panel opened from the user cluster lands keyboard focus on its first
/// control in Tab order, a discrete beat after it mounts; a panel opened any
/// other way, or from a stale press, leaves focus where it was
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

  Future<void> openFromCluster(WidgetTester tester) async {
    await tester.pumpWidget(host(panelOpen: false));
    cluster.requestFocus();
    await tester.pump();
    expect(cluster.hasPrimaryFocus, isTrue);
  }

  testWidgets("an armed open lands focus on the panel's first control", (
    tester,
  ) async {
    await openFromCluster(tester);
    intent.arm();
    await tester.pumpWidget(host(panelOpen: true));
    await tester.pump();
    expect(cluster.hasPrimaryFocus, isTrue, reason: 'one discrete beat later');
    await tester.pump(PanelEntryFocus.claimDelay);
    expect(close.hasPrimaryFocus, isTrue);

    // The claim scope is not itself a Tab stop: Tab moves on inside the panel.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(practice.hasPrimaryFocus, isTrue);
  });

  testWidgets('an open without the intent leaves focus where it was', (
    tester,
  ) async {
    await openFromCluster(tester);
    await tester.pumpWidget(host(panelOpen: true));
    await tester.pump(PanelEntryFocus.claimDelay);
    expect(cluster.hasPrimaryFocus, isTrue);
    expect(close.hasPrimaryFocus, isFalse);
  });

  testWidgets('a stale arm is ignored', (tester) async {
    await openFromCluster(tester);
    intent.arm();
    now = now.add(PanelEntryIntent.ttl + const Duration(seconds: 1));
    await tester.pumpWidget(host(panelOpen: true));
    await tester.pump(PanelEntryFocus.claimDelay);
    expect(cluster.hasPrimaryFocus, isTrue);
  });

  testWidgets('in a right-to-left panel the leading control is on the right', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: PanelEntryFocus(
              intent: intent..arm(),
              child: Row(
                children: [
                  IconButton(
                    focusNode: close,
                    tooltip: 'Close',
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
      ),
    );
    await tester.pump(PanelEntryFocus.claimDelay);
    // Row lays its first child out on the right in RTL: that is the leading
    // control, and the one to land on.
    expect(close.hasPrimaryFocus, isTrue);
  });

  testWidgets('an arm is consumed once', (tester) async {
    await openFromCluster(tester);
    intent.arm();
    await tester.pumpWidget(host(panelOpen: true));
    await tester.pump(PanelEntryFocus.claimDelay);
    expect(close.hasPrimaryFocus, isTrue);
    expect(intent.take(), isFalse);
  });
}
