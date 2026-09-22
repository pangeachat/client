import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/tutorials/tutorial_copy.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_state_machine.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_widget.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// #9050 — the tutorial card for a screen reader and a keyboard: the message
/// is the tap-anywhere, named and focusable; a tap step hides the app behind
/// it and an armed step does not; Tab stays in the card, Enter activates what
/// has focus, Escape is the card's way out; focus goes back where it came from.
/// Design: tutorials.instructions.md § Accessibility.
void main() {
  const targetId = 'tutorial-semantics-target';
  const messageKey = ValueKey('tutorial-message');
  const behindLabel = 'behind the overlay';

  late L10n l10n;
  late int forwards;
  late int skips;
  late int resets;

  setUpAll(() async {
    // Real async (a deferred library); the fake clock in a test body never
    // gets to it.
    l10n = await lookupL10n(const Locale('en'));
  });

  setUp(() {
    forwards = 0;
    skips = 0;
    resets = 0;
    // Rings render only in traditional (keyboard) highlight mode.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDownAll(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  TutorialStepData stepData({TutorialStepArming? arming}) =>
      TutorialStepData.single(
        targetKey: targetId,
        canShowNextStep: () => true,
        arming: arming,
      );

  /// A [type] tutorial whose every step lights the harness target.
  TutorialModel model(TutorialEnum type, {TutorialStepArming? arming}) =>
      TutorialModel(
        tutorialType: type,
        stepsData: List.generate(
          type.stepCount,
          (_) => stepData(arming: arming),
        ),
      );

  Widget harness({
    required TutorialModel? tutorial,
    int stepIndex = 0,
    TutorialSequenceKind? kind = TutorialSequenceKind.chat,
    int totalSteps = 4,
    FocusNode? behindFocus,
  }) {
    final target = MatrixState.pAnyState.layerLinkAndKey(targetId);
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Stack(
          children: [
            // Stands in for the app under the overlay.
            Positioned(
              left: 0,
              top: 0,
              child: TextButton(
                focusNode: behindFocus,
                onPressed: () {},
                child: const Text(behindLabel),
              ),
            ),
            Positioned(
              left: 100,
              top: 300,
              child: CompositedTransformTarget(
                link: target.link,
                child: SizedBox(key: target.key, width: 40, height: 40),
              ),
            ),
            if (tutorial != null)
              TutorialOverlayWidget(
                model: TutorialOverlayState(
                  activeTutorial: tutorial,
                  stepIndex: stepIndex,
                ),
                sequenceKind: kind,
                forward: () => forwards++,
                reset: () => resets++,
                skipSequence: () => skips++,
                setTutorialTransitioning: (_) {},
                completedSteps: stepIndex + 1,
                totalSteps: totalSteps,
              ),
          ],
        ),
      ),
    );
  }

  /// The overlay asks for a frame every frame while it is up (its target
  /// monitor), so pumpAndSettle never settles: pump a fixed few instead —
  /// enough for the localizations, the post-frame visibility flip, and the
  /// spotlight measurement.
  Future<void> pumpFrames(WidgetTester tester, [int count = 6]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// A step callback waits out the animation duration before advancing.
  Future<void> pumpTransition(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 400));

  SemanticsNode messageNode(WidgetTester tester) =>
      tester.getSemantics(find.byKey(messageKey));

  /// What a screen reader would walk, in order.
  List<String> allLabels(WidgetTester tester) => [
    for (final node in tester.semantics.simulatedAccessibilityTraversal())
      if (node.label.isNotEmpty) node.label,
  ];

  String focusedLabel() =>
      FocusManager.instance.primaryFocus?.debugLabel ?? '<none>';

  group('a tap step', () {
    testWidgets(
      'the message is one focused, announced button named by its copy, and '
      'activating it advances',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          harness(tutorial: model(TutorialEnum.selectModeButtons)),
        );
        await pumpFrames(tester);

        final node = messageNode(tester);
        final data = node.getSemanticsData();
        expect(node.label, l10n.readingAssistanceTutorialCollectToken);
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.flagsCollection.isLiveRegion, isTrue);
        expect(node.flagsCollection.isFocused, Tristate.isTrue);
        expect(node.hint, l10n.continueText);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(focusedLabel(), 'tutorial message');

        node.owner!.performAction(node.id, SemanticsAction.tap);
        await pumpTransition(tester);
        expect(forwards, 1);

        handle.dispose();
      },
    );

    testWidgets('hides the app under it from assistive tech', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        harness(tutorial: model(TutorialEnum.selectModeButtons)),
      );
      await pumpFrames(tester);

      final labels = allLabels(tester);
      expect(labels, isNot(contains(behindLabel)));
      expect(labels, contains(l10n.skip));
      expect(labels, contains('1 / 4'));

      handle.dispose();
    });

    testWidgets('every tappable node is named', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        harness(tutorial: model(TutorialEnum.selectModeButtons)),
      );
      await pumpFrames(tester);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets(
      'Enter advances on the message and skips on Skip; Tab cycles the card',
      (tester) async {
        await tester.pumpWidget(
          harness(tutorial: model(TutorialEnum.selectModeButtons)),
        );
        await pumpFrames(tester);
        expect(focusedLabel(), 'tutorial message');

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await pumpFrames(tester, 2);
        expect(focusedLabel(), isNot('tutorial message'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await pumpTransition(tester);
        expect(skips, 1);
        expect(forwards, 0);

        // Only two controls on this card, so the cycle is back at the message.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await pumpFrames(tester, 2);
        expect(focusedLabel(), 'tutorial message');
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await pumpTransition(tester);
        expect(forwards, 1);
        expect(skips, 1);
      },
    );

    testWidgets('Escape skips the sequence where Skip shows', (tester) async {
      await tester.pumpWidget(
        harness(tutorial: model(TutorialEnum.selectModeButtons)),
      );
      await pumpFrames(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester, 2);
      expect(skips, 1);
      expect(forwards, 0);
    });

    testWidgets('Escape does nothing on the greeting', (tester) async {
      await tester.pumpWidget(
        harness(
          tutorial: TutorialModel.welcome(const TutorialGreeting('Hello')),
          kind: TutorialSequenceKind.worldOrientation,
          totalSteps: 3,
        ),
      );
      await pumpFrames(tester);
      expect(find.text(l10n.skip), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester, 2);
      expect(skips, 0);
      expect(forwards, 0);
      expect(focusedLabel(), 'tutorial message');
    });

    testWidgets('Escape does nothing on a one-step run', (tester) async {
      await tester.pumpWidget(
        harness(tutorial: model(TutorialEnum.readingAssistance), totalSteps: 1),
      );
      await pumpFrames(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester, 2);
      expect(skips, 0);
    });

    testWidgets('Tab is consumed on a card with one control', (tester) async {
      // With nowhere to move, the default focus action reports Tab
      // unhandled, and on web the browser then parks focus outside the card.
      await tester.pumpWidget(
        harness(tutorial: model(TutorialEnum.readingAssistance), totalSteps: 1),
      );
      await pumpFrames(tester);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.tab), isTrue);
      await pumpFrames(tester, 2);
      expect(focusedLabel(), 'tutorial message');
    });

    testWidgets('hands focus back to where it was when the run ends', (
      tester,
    ) async {
      final behindFocus = FocusNode(debugLabel: 'behind');
      addTearDown(behindFocus.dispose);
      await tester.pumpWidget(
        harness(tutorial: null, behindFocus: behindFocus),
      );
      await pumpFrames(tester);
      behindFocus.requestFocus();
      await pumpFrames(tester, 2);
      expect(focusedLabel(), 'behind');

      await tester.pumpWidget(
        harness(
          tutorial: model(TutorialEnum.selectModeButtons),
          behindFocus: behindFocus,
        ),
      );
      await pumpFrames(tester);
      expect(focusedLabel(), 'tutorial message');

      await tester.pumpWidget(
        harness(tutorial: null, behindFocus: behindFocus),
      );
      await pumpFrames(tester, 2);
      expect(focusedLabel(), 'behind');
    });
  });

  group('a branch step', () {
    testWidgets(
      'the message is a focused group, not a button; Enter does nothing; '
      'Escape declines',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          harness(
            tutorial: model(TutorialEnum.appTour),
            kind: TutorialSequenceKind.appTour,
            totalSteps: 6,
          ),
        );
        await pumpFrames(tester);

        final node = messageNode(tester);
        final data = node.getSemanticsData();
        expect(node.label, l10n.tutorialAppTourOffer);
        expect(node.flagsCollection.isButton, isFalse);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        expect(node.flagsCollection.isFocused, Tristate.isTrue);
        expect(allLabels(tester), contains(l10n.tutorialAppTourAccept));

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await pumpTransition(tester);
        expect(forwards, 0);
        expect(skips, 0);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await pumpFrames(tester, 2);
        expect(skips, 1);

        handle.dispose();
      },
    );
  });

  group('an armed step', () {
    testWidgets(
      'leaves the app reachable, and activating the message dismisses',
      (tester) async {
        final handle = tester.ensureSemantics();
        final signal = ValueNotifier(false);
        addTearDown(signal.dispose);
        await tester.pumpWidget(
          harness(
            tutorial: model(
              TutorialEnum.activityRoles,
              arming: TutorialStepArming(
                signal: signal,
                isSatisfied: () => signal.value,
              ),
            ),
            kind: TutorialSequenceKind.activityRoles,
            totalSteps: 1,
          ),
        );
        await pumpFrames(tester);

        expect(allLabels(tester), contains(behindLabel));

        final node = messageNode(tester);
        expect(node.hint, l10n.dismiss);
        expect(node.flagsCollection.isButton, isTrue);
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await pumpFrames(tester, 2);
        expect(forwards, 1);

        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      },
    );
  });
}
