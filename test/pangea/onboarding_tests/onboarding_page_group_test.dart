import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_header.dart';
import 'package:fluffychat/routes/onboarding/onboarding_page_group.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_step_body.dart';

/// #7582 — a step is one named group that claims focus a beat after it is
/// swapped in, with the header's Back button and progress bar as its direct
/// children beside the named center-content group.
void main() {
  Widget page({
    required int step,
    required FocusNode choose,
    bool scrollable = false,
  }) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: OnboardingPageGroup(
      stepKey: step,
      label: 'Step $step page',
      child: Scaffold(
        appBar: OnboardingHeader(
          hasPrevStep: true,
          progress: 0.4,
          step: step,
          totalSteps: 5,
          onBack: () {},
        ),
        body: Column(
          children: [
            // A real swap replaces the content subtree, disposing its controls.
            KeyedSubtree(
              key: ValueKey(step),
              child: OnboardingStepBody(
                label: 'Question $step',
                scrollable: scrollable,
                child: ElevatedButton(
                  focusNode: choose,
                  onPressed: () {},
                  child: const Text('Choose'),
                ),
              ),
            ),
            ElevatedButton(onPressed: () {}, child: const Text('Next')),
          ],
        ),
      ),
    ),
  );

  Future<void> pumpPage(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    // The async L10n delegate leaves the home empty on the very first frame.
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  FocusNode nodeOf(WidgetTester tester, Finder widget) => tester
      .widget<Focus>(
        find.descendant(of: widget, matching: find.byType(Focus)).first,
      )
      .focusNode!;

  testWidgets(
    'the step claims focus a beat after mounting, named and flat-headed',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final choose = FocusNode();
      addTearDown(choose.dispose);

      await pumpPage(tester, page(step: 1, choose: choose));
      final group = nodeOf(tester, find.byType(OnboardingPageGroup));
      expect(group.hasPrimaryFocus, isFalse);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(group.hasPrimaryFocus, isTrue);
      // Not a Tab stop: keyboard users go straight to the controls inside.
      expect(group.skipTraversal, isTrue);
      final pageNode = tester.getSemantics(find.byType(OnboardingPageGroup));
      expect(
        pageNode,
        isSemantics(label: 'Step 1 page', isFocusable: true, isFocused: true),
      );

      // Back and the progress bar are direct children of the step, beside the
      // named content group — one step up from the content reaches them.
      expect(tester.getSemantics(find.byType(BackButton)).parent, pageNode);
      final progress = tester.getSemantics(
        find.bySemanticsLabel('Step 1 of 5'),
      );
      expect(progress.parent, pageNode);
      final content = tester.getSemantics(find.byType(OnboardingStepBody));
      expect(content, isSemantics(label: 'Question 1'));
      expect(content.parent, pageNode);
      expect(tester.getSemantics(find.text('Choose')).parent, content);
      expect(tester.getSemantics(find.text('Next')).parent, pageNode);

      semantics.dispose();
    },
  );

  testWidgets('a swap under a focused control lands on the new step', (
    tester,
  ) async {
    final choose = FocusNode();
    addTearDown(choose.dispose);

    await pumpPage(tester, page(step: 1, choose: choose));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // Back has been used, then a choice is pressed: both sit in the scope's
    // focus history when the swap disposes the choice.
    // The button owns its node internally; read it from inside its subtree.
    final back = Focus.of(
      tester.element(
        find.descendant(
          of: find.byType(BackButton),
          matching: find.byType(Icon),
        ),
      ),
    );
    back.requestFocus();
    await tester.pump();
    choose.requestFocus();
    await tester.pump();
    expect(choose.hasPrimaryFocus, isTrue);

    await tester.pumpWidget(page(step: 2, choose: choose));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(back.hasPrimaryFocus, isFalse);
    final group = nodeOf(tester, find.byType(OnboardingPageGroup));
    expect(group.hasPrimaryFocus, isTrue);
    expect(
      tester
          .widget<OnboardingPageGroup>(find.byType(OnboardingPageGroup))
          .label,
      'Step 2 page',
    );
  });

  testWidgets('a scrolling step names its scroll region as the content group', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final choose = FocusNode();
    addTearDown(choose.dispose);

    await pumpPage(tester, page(step: 1, choose: choose, scrollable: true));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final pageNode = tester.getSemantics(find.byType(OnboardingPageGroup));
    // The named group is the scroll region itself: no extra level between
    // the choices and the header.
    final content = tester.getSemantics(find.byType(OnboardingStepBody));
    expect(content, isSemantics(label: 'Question 1'));
    expect(content.parent, pageNode);
    expect(tester.getSemantics(find.text('Choose')).parent, content);

    semantics.dispose();
  });
}
