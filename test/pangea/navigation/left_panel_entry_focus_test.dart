import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_entry_intent.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/left_panel/workspace_left_panel.dart';
import 'package:fluffychat/routes/world/right_panel/panel_entry_focus.dart';

/// A course the rail just opened lands focus on the left panel's own named
/// group, the way a panel the cluster opened does (routing.instructions.md,
/// "Every panel is a named group to assistive tech"): the left column's
/// dispatcher authors the same [PanelEntryFocus] the right column does, so an
/// armed [PanelEntryIntent] is taken by the course panel that mounts.
void main() {
  late FocusNode rail;

  setUp(() {
    rail = FocusNode(debugLabel: 'rail');
    // Drop any arm a previous test left on the app-wide singleton.
    PanelEntryIntent.instance.take();
  });
  tearDown(() => rail.dispose());

  // The rail item stands in for the pressed course avatar. A course token
  // with no course context renders an empty surface, which is all the group
  // needs and keeps the host free of a Matrix client.
  Widget host({required bool panelOpen}) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            focusNode: rail,
            onPressed: () {},
            child: const Text('Course A'),
          ),
          if (panelOpen)
            Expanded(
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: WorkspaceLeftPanel(
                  token: const CoursePanelToken(),
                  currentUri: Uri.parse('/'),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  /// Whether the panel's named group is the node assistive tech is on.
  bool groupFocused(WidgetTester tester) =>
      tester.semantics.simulatedAccessibilityTraversal().any(
        (n) =>
            n.getSemanticsData().label == 'Course page' &&
            n.flagsCollection.isFocused == Tristate.isTrue,
      );

  Future<void> focusRail(WidgetTester tester) async {
    await tester.pumpWidget(host(panelOpen: false));
    // The localized app mounts its home once the delegates have loaded.
    await tester.pumpAndSettle();
    expect(find.text('Course A'), findsOneWidget);
    rail.requestFocus();
    await tester.pump();
    expect(rail.hasPrimaryFocus, isTrue);
  }

  testWidgets('a course opened from the rail lands focus on its group', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await focusRail(tester);
    PanelEntryIntent.instance.arm();
    await tester.pumpWidget(host(panelOpen: true));
    await tester.pump(PanelEntryFocus.claimDelay);
    expect(rail.hasPrimaryFocus, isFalse);
    expect(groupFocused(tester), isTrue);
    handle.dispose();
  });

  testWidgets('a course panel opened without the intent leaves focus', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await focusRail(tester);
    await tester.pumpWidget(host(panelOpen: true));
    await tester.pump(PanelEntryFocus.claimDelay);
    expect(rail.hasPrimaryFocus, isTrue);
    expect(groupFocused(tester), isFalse);
    handle.dispose();
  });
}
