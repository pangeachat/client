import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/overlay/any_state_holder.dart';
import 'package:fluffychat/features/tutorials/tutorial_constants.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_controller.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_widget.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_tutorial_progress.dart';

/// CLIENT-EN9: an armed step whose action the learner has already done (the
/// start page's open-sessions step, for a learner already in a session of the
/// activity) completes at launch. The overlay must not open for it.
void main() {
  const targetId = 'tutorial-armed-launch-target';
  const sequenceKey = TutorialConstants.sequenceOverlayKey;
  const noActiveTutorial =
      'error message: TutorialOverlayWidget launched with no active tutorial';

  late BuildContext hostContext;
  late List<String> printed;
  late Map<TutorialEnum, int> saved;
  late TutorialOverlayController controller;

  setUpAll(() async {
    // Real async (a deferred library); the fake clock never gets to it.
    await lookupL10n(const Locale('en'));
  });

  setUp(() {
    MatrixState.pAnyState = PangeaAnyState();
    printed = [];
    saved = {};
    controller = TutorialOverlayController(
      progress: FakeTutorialProgress(progressLog: saved),
    );
  });

  Widget app() {
    final target = MatrixState.pAnyState.layerLinkAndKey(targetId);
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            hostContext = context;
            return Stack(
              children: [
                Positioned(
                  left: 100,
                  top: 300,
                  child: SizedBox(key: target.key, width: 200, height: 80),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The start page's launcher shape: an await (its scroll into view), then
  /// one armed step.
  TutorialLauncher startPageLauncher(
    TutorialEnum tutorial, {
    required bool Function() isDone,
    Listenable? signal,
  }) => () async {
    await Future<void>.microtask(() {});
    controller.launchTutorial(
      context: hostContext,
      tutorial: TutorialModel(
        tutorialType: tutorial,
        stepsData: [
          TutorialStepData.single(
            targetKey: targetId,
            canShowNextStep: () => true,
            arming: TutorialStepArming(
              signal: signal ?? ValueNotifier(0),
              isSatisfied: isDone,
            ),
          ),
        ],
      ),
      isFocused: true,
    );
  };

  /// Runs [body] with what the app prints going to [printed].
  Future<void> capturingPrints(Future<void> Function() body) async {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
    try {
      await body();
    } finally {
      debugPrint = original;
    }
  }

  /// Pumps [count] frames, failing on any framework exception: the old path
  /// also tripped an assert in debug builds.
  Future<void> frames(WidgetTester tester, [int count = 6]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
  }

  /// The app and its localizations, which load a frame or two after the
  /// first pump; the host context exists only once they have.
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await frames(tester);
  }

  bool overlayOpen() =>
      MatrixState.pAnyState.isOverlayOpen(overlayKey: sequenceKey);

  testWidgets('a step already done at launch completes without an overlay', (
    tester,
  ) async {
    await pumpApp(tester);
    controller.registerLauncher(
      TutorialEnum.openSessions,
      startPageLauncher(TutorialEnum.openSessions, isDone: () => true),
    );

    await capturingPrints(() async {
      controller.requestSequence(TutorialSequences.openSessionsSequence);
      // The launch, before any frame: nothing may have been opened for it.
      await tester.idle();
      expect(overlayOpen(), isFalse);
      await frames(tester);
    });

    expect(printed, isNot(contains(noActiveTutorial)));
    expect(
      printed,
      contains(
        'event: tutorial_progress - parameters: '
        '{tutorial_name: openSessions, tutorial_step: 0}',
      ),
    );
    expect(saved[TutorialEnum.openSessions], 1, reason: 'marked seen');
    expect(controller.hasActiveSequence, isFalse);
    expect(find.byType(TutorialOverlayWidget), findsNothing);
  });

  testWidgets('a step not yet done shows, and doing it ends the sequence', (
    tester,
  ) async {
    await pumpApp(tester);
    var joined = false;
    final signal = ValueNotifier(0);
    controller.registerLauncher(
      TutorialEnum.openSessions,
      startPageLauncher(
        TutorialEnum.openSessions,
        isDone: () => joined,
        signal: signal,
      ),
    );

    await capturingPrints(() async {
      controller.requestSequence(TutorialSequences.openSessionsSequence);
      await frames(tester);
      expect(
        controller.state.model.activeTutorial?.tutorialType,
        TutorialEnum.openSessions,
      );
      expect(overlayOpen(), isTrue);
      expect(find.byType(TutorialOverlayWidget), findsOneWidget);

      joined = true;
      signal.value++;
      await frames(tester);
    });

    expect(printed, isNot(contains(noActiveTutorial)));
    expect(saved[TutorialEnum.openSessions], 1);
    expect(controller.hasActiveSequence, isFalse);
    expect(overlayOpen(), isFalse);
  });

  testWidgets('a sequence queued behind one already done gets its overlay', (
    tester,
  ) async {
    await pumpApp(tester);
    controller.registerLauncher(
      TutorialEnum.openSessions,
      startPageLauncher(TutorialEnum.openSessions, isDone: () => true),
    );
    // No await before launching, like the world map's app tour and map
    // introduction: it opens its overlay during the queue drain.
    controller.registerLauncher(TutorialEnum.activityRoles, () async {
      controller.launchTutorial(
        context: hostContext,
        tutorial: TutorialModel(
          tutorialType: TutorialEnum.activityRoles,
          stepsData: [
            TutorialStepData.single(
              targetKey: targetId,
              canShowNextStep: () => true,
            ),
          ],
        ),
        isFocused: true,
      );
    });

    await capturingPrints(() async {
      controller.requestSequence(TutorialSequences.openSessionsSequence);
      expect(
        controller.requestSequence(TutorialSequences.activityRolesSequence),
        isFalse,
        reason: 'queued while openSessions launches',
      );
      await frames(tester);
    });

    expect(
      controller.state.model.activeTutorial?.tutorialType,
      TutorialEnum.activityRoles,
    );
    expect(overlayOpen(), isTrue);
    expect(find.byType(TutorialOverlayWidget), findsOneWidget);
  });
}
