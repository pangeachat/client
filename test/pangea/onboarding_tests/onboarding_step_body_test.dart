import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_step_body.dart';

/// #7582 — a step's center content is a named group that claims focus a beat
/// after it mounts, so a screen reader lands on the new step's content after a
/// swap instead of the app bar's Back button or the page root.
void main() {
  Widget shell({
    required int step,
    required FocusNode back,
    required FocusNode next,
  }) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          focusNode: back,
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {},
        ),
      ),
      body: OnboardingStepBody(
        key: ValueKey(step),
        label: 'Step $step',
        child: Column(
          children: [
            const Text('Question'),
            ElevatedButton(
              focusNode: next,
              onPressed: () {},
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    ),
  );

  FocusNode bodyNode(WidgetTester tester) => tester
      .widget<Focus>(
        find
            .descendant(
              of: find.byType(OnboardingStepBody),
              matching: find.byType(Focus),
            )
            .first,
      )
      .focusNode!;

  testWidgets('claims focus a beat after mounting, as a named group', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final back = FocusNode();
    final next = FocusNode();
    addTearDown(() {
      back.dispose();
      next.dispose();
    });

    await tester.pumpWidget(shell(step: 1, back: back, next: next));
    expect(bodyNode(tester).hasPrimaryFocus, isFalse);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(bodyNode(tester).hasPrimaryFocus, isTrue);
    // Not a Tab stop: keyboard users go straight to the controls inside.
    expect(bodyNode(tester).skipTraversal, isTrue);
    expect(
      tester.getSemantics(find.byType(OnboardingStepBody)),
      isSemantics(label: 'Step 1', isFocusable: true, isFocused: true),
    );
    // Children stay their own nodes; the group's name is only its title.
    expect(
      tester.getSemantics(find.text('Next')),
      isSemantics(label: 'Next', isButton: true),
    );
    expect(
      tester.getSemantics(find.text('Question')),
      isSemantics(label: 'Question'),
    );

    semantics.dispose();
  });

  testWidgets('a swap under a focused control lands on the new body', (
    tester,
  ) async {
    final back = FocusNode();
    final next = FocusNode();
    addTearDown(() {
      back.dispose();
      next.dispose();
    });

    await tester.pumpWidget(shell(step: 1, back: back, next: next));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // Back has been used, then Next is pressed: both sit in the scope's focus
    // history when the swap disposes Next.
    back.requestFocus();
    await tester.pump();
    next.requestFocus();
    await tester.pump();
    expect(next.hasPrimaryFocus, isTrue);

    await tester.pumpWidget(shell(step: 2, back: back, next: next));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(back.hasPrimaryFocus, isFalse);
    expect(bodyNode(tester).hasPrimaryFocus, isTrue);
    expect(
      tester.widget<OnboardingStepBody>(find.byType(OnboardingStepBody)).label,
      'Step 2',
    );
  });
}
