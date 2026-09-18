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

  // A page pushed or popped within a panel — a course section's "See all",
  // the back arrow out of it — is a different token, so the panel remounts and
  // the pressed control goes with it. armForSwap drops the focus history
  // before it arms, as the onboarding swap does (#7582): otherwise the
  // framework restores focus to the last control still alive, the rail item,
  // until the claim (#9154).
  testWidgets('a push that removes the pressed control lands on the new page', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final rail = FocusNode(debugLabel: 'rail');
    final seeAll = FocusNode(debugLabel: 'seeAll');
    addTearDown(rail.dispose);
    addTearDown(seeAll.dispose);

    // The shell's shape: the rail, then the panel keyed on its token.
    Widget pushHost({required bool pushed}) => MaterialApp(
      home: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Scaffold(
          body: Column(
            children: [
              FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: ElevatedButton(
                  focusNode: rail,
                  onPressed: () {},
                  child: const Text('Course A'),
                ),
              ),
              FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: PanelEntryFocus(
                    key: ValueKey(pushed),
                    label: pushed ? 'Vocab page' : 'Course page',
                    sortKey: const OrdinalSortKey(2),
                    intent: intent,
                    child: pushed
                        ? IconButton(
                            focusNode: close,
                            tooltip: 'Back',
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () {},
                          )
                        : TextButton(
                            focusNode: seeAll,
                            onPressed: () {},
                            child: const Text('See all'),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // The learner came from the rail, then reached "See all".
    await tester.pumpWidget(pushHost(pushed: false));
    rail.requestFocus();
    await tester.pump();
    seeAll.requestFocus();
    await tester.pump();
    expect(seeAll.hasPrimaryFocus, isTrue);

    // What the opener does, then the navigation's rebuild.
    intent.armForSwap();
    await tester.pumpWidget(pushHost(pushed: true));
    await tester.pump();
    expect(rail.hasPrimaryFocus, isFalse, reason: 'no older control restored');

    await tester.pump(PanelEntryFocus.claimDelay);
    expect(groupFocused(tester), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(close.hasPrimaryFocus, isTrue);
    handle.dispose();
  });

  // A closed detail returns focus to its parent. Beside the detail the parent
  // is already on screen, so nothing mounts: the arm names it, and the panel
  // on screen takes it (#9154). An arm that names no one is never taken by a
  // panel on screen, so it still reaches the panel that mounts.
  group('a named arm', () {
    late FocusNode invite;

    setUp(() => invite = FocusNode(debugLabel: 'invite'));
    tearDown(() => invite.dispose());

    // The course card with the invite page open beside it.
    Widget besideHost({required bool detailOpen}) => MaterialApp(
      home: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Scaffold(
          body: Row(
            children: [
              FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: PanelEntryFocus(
                  label: 'Course page',
                  sortKey: const OrdinalSortKey(1),
                  panel: 'course',
                  intent: intent,
                  child: TextButton(
                    focusNode: invite,
                    onPressed: () {},
                    child: const Text('Invite'),
                  ),
                ),
              ),
              if (detailOpen)
                FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: PanelEntryFocus(
                    label: 'Invite page',
                    sortKey: const OrdinalSortKey(2),
                    panel: 'coursepage',
                    intent: intent,
                    child: IconButton(
                      focusNode: close,
                      tooltip: 'Close Invite',
                      icon: const Icon(Icons.close),
                      onPressed: () {},
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    bool courseFocused(WidgetTester tester) =>
        tester.semantics.simulatedAccessibilityTraversal().any(
          (n) =>
              n.getSemanticsData().label == 'Course page' &&
              n.flagsCollection.isFocused == Tristate.isTrue,
        );

    testWidgets('is taken by that panel while it is already on screen', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(besideHost(detailOpen: true));
      close.requestFocus();
      await tester.pump();
      expect(close.hasPrimaryFocus, isTrue);

      // What the close control does, then the navigation's rebuild.
      intent.armForSwap(target: 'course');
      await tester.pumpWidget(besideHost(detailOpen: false));
      await tester.pump(PanelEntryFocus.claimDelay);
      expect(courseFocused(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(invite.hasPrimaryFocus, isTrue);
      handle.dispose();
    });

    testWidgets('that names no one is left for the panel that mounts', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(besideHost(detailOpen: true));
      intent.arm();
      await tester.pump(PanelEntryFocus.claimDelay);
      expect(courseFocused(tester), isFalse);
      expect(intent.take(), isTrue, reason: 'still there for a mount');
      handle.dispose();
    });
  });
}
