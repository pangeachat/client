import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_controller.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_state_machine.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/features/tutorials/tutorial_state_transition_events.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';

// Sequences used across tests.
// readingAssistance: 1 step  |  selectModeButtons: 4 steps  |  writingAssistance: 1 step
const _single = [TutorialEnum.readingAssistance];
const _multiStep = [TutorialEnum.selectModeButtons];
const _full = [
  TutorialEnum.readingAssistance,
  TutorialEnum.selectModeButtons,
  TutorialEnum.writingAssistance,
];

TutorialStepData _stepData() =>
    TutorialStepData.single(targetKey: 'test_key', canShowNextStep: () => true);

TutorialModel _model(TutorialEnum type) => TutorialModel(
  tutorialType: type,
  stepsData: List.generate(type.stepCount, (_) => _stepData()),
);

TutorialModel _readingModel() => _model(TutorialEnum.readingAssistance);

TutorialModel _selectModel() => _model(TutorialEnum.selectModeButtons);

/// Stands in for the learner's profile: every tutorial unseen unless named in
/// [seen], resuming at whatever [resumeSteps] says.
class _FakeProgress extends TutorialProgressSource {
  final Set<TutorialEnum> seen;
  final Map<TutorialEnum, int> resumeSteps;

  const _FakeProgress({this.seen = const {}, this.resumeSteps = const {}});

  @override
  bool isEnabled(TutorialEnum tutorial) => !seen.contains(tutorial);

  @override
  int resumeStep(TutorialEnum tutorial) => resumeSteps[tutorial] ?? 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TutorialOverlayStateMachine', () {
    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------
    group('initial state', () {
      test(
        'tutorialIndex=0, stepIndex=0, no active tutorial, not transitioning',
        () {
          final sm = TutorialOverlayStateMachine(_single);
          expect(sm.model.tutorialIndex, 0);
          expect(sm.model.stepIndex, 0);
          expect(sm.model.activeTutorial, isNull);
          expect(sm.model.isStepTransitioning, false);
        },
      );

      test(
        'empty sequence: tutorialType is null, totalStepsInSequence is 0',
        () {
          final sm = TutorialOverlayStateMachine([]);
          expect(sm.tutorialType, isNull);
          expect(sm.totalStepsInSequence, 0);
        },
      );

      test('initialStepIndex parameter is respected', () {
        final sm = TutorialOverlayStateMachine(_multiStep, initialStepIndex: 2);
        expect(sm.model.stepIndex, 2);
      });
    });

    // -------------------------------------------------------------------------
    // LaunchTutorialEvent
    // -------------------------------------------------------------------------
    group('dispatch — LaunchTutorialEvent', () {
      test('sets activeTutorial', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(LaunchTutorialEvent(_readingModel()));
        expect(
          sm.model.activeTutorial?.tutorialType,
          TutorialEnum.readingAssistance,
        );
      });

      test('does not change tutorialIndex or stepIndex', () {
        final sm = TutorialOverlayStateMachine(_full);
        sm.dispatch(const ForwardTutorialEvent()); // tutorialIndex → 1
        sm.dispatch(LaunchTutorialEvent(_selectModel()));
        expect(sm.model.tutorialIndex, 1);
        expect(sm.model.stepIndex, 0);
      });

      test('notifies listeners', () {
        final sm = TutorialOverlayStateMachine(_single);
        int count = 0;
        sm.addListener(() => count++);
        sm.dispatch(LaunchTutorialEvent(_readingModel()));
        expect(count, 1);
      });
    });

    // -------------------------------------------------------------------------
    // TutorialTransitionEvent
    // -------------------------------------------------------------------------
    group('dispatch — TutorialTransitionEvent', () {
      test('sets isStepTransitioning to true', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(const TutorialTransitionEvent(true));
        expect(sm.model.isStepTransitioning, true);
      });

      test('sets isStepTransitioning back to false', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(const TutorialTransitionEvent(true));
        sm.dispatch(const TutorialTransitionEvent(false));
        expect(sm.model.isStepTransitioning, false);
      });
    });

    // -------------------------------------------------------------------------
    // ForwardTutorialEvent
    // -------------------------------------------------------------------------
    group('dispatch — ForwardTutorialEvent', () {
      test('increments stepIndex within a multi-step tutorial', () {
        final sm = TutorialOverlayStateMachine(_multiStep);
        sm.dispatch(const ForwardTutorialEvent());
        expect(sm.model.stepIndex, 1);
        sm.dispatch(const ForwardTutorialEvent());
        expect(sm.model.stepIndex, 2);
      });

      test(
        'advances to next tutorial at last step, resets stepIndex, clears activeTutorial',
        () {
          final sm = TutorialOverlayStateMachine(_full);
          sm.dispatch(LaunchTutorialEvent(_readingModel()));
          // readingAssistance has 1 step — forward should move to selectModeButtons
          sm.dispatch(const ForwardTutorialEvent());
          expect(sm.model.tutorialIndex, 1);
          expect(sm.model.stepIndex, 0);
          expect(sm.model.activeTutorial, isNull);
          expect(sm.tutorialType, TutorialEnum.selectModeButtons);
        },
      );

      test('increments past end of sequence, tutorialType becomes null', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(const ForwardTutorialEvent());
        expect(sm.model.tutorialIndex, 1);
        expect(sm.tutorialType, isNull);
      });

      test('stays safe when tutorialIndex already exceeds sequence length', () {
        final sm = TutorialOverlayStateMachine([]);
        sm.dispatch(const ForwardTutorialEvent());
        expect(sm.model.stepIndex, 0);
        expect(sm.model.activeTutorial, isNull);
      });
    });

    // -------------------------------------------------------------------------
    // BackTutorialEvent
    // -------------------------------------------------------------------------
    group('dispatch — BackTutorialEvent', () {
      test('decrements stepIndex within a multi-step tutorial', () {
        final sm = TutorialOverlayStateMachine(_multiStep);
        sm.dispatch(const ForwardTutorialEvent()); // step 1
        sm.dispatch(const ForwardTutorialEvent()); // step 2
        sm.dispatch(const BackTutorialEvent());
        expect(sm.model.stepIndex, 1);
        sm.dispatch(const BackTutorialEvent());
        expect(sm.model.stepIndex, 0);
      });

      test(
        'goes back to last step of previous tutorial when at step 0, clears activeTutorial',
        () {
          final sm = TutorialOverlayStateMachine(_full);
          sm.dispatch(
            const ForwardTutorialEvent(),
          ); // → selectModeButtons (index 1)
          sm.dispatch(LaunchTutorialEvent(_selectModel()));
          sm.dispatch(
            const BackTutorialEvent(),
          ); // → readingAssistance (index 0)
          expect(sm.model.tutorialIndex, 0);
          // readingAssistance has 1 step: last step index is 0
          expect(sm.model.stepIndex, 0);
          expect(sm.model.activeTutorial, isNull);
          expect(sm.tutorialType, TutorialEnum.readingAssistance);
        },
      );

      test(
        'goes back to last step (index 2) of a 4-step previous tutorial',
        () {
          final sm = TutorialOverlayStateMachine(_full);
          // Advance through selectModeButtons into writingAssistance
          sm.dispatch(const ForwardTutorialEvent()); // → selectModeButtons
          sm.dispatch(const ForwardTutorialEvent()); // step 1
          sm.dispatch(const ForwardTutorialEvent()); // step 2
          sm.dispatch(const ForwardTutorialEvent()); // step 3
          sm.dispatch(
            const ForwardTutorialEvent(),
          ); // → writingAssistance (index 2)
          sm.dispatch(const BackTutorialEvent()); // ← selectModeButtons step 2
          expect(sm.model.tutorialIndex, 1);
          expect(sm.model.stepIndex, 3);
        },
      );

      test('sets tutorialIndex to -1 when backing past first tutorial', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(const BackTutorialEvent());
        expect(sm.model.tutorialIndex, -1);
        expect(sm.model.stepIndex, 0);
        expect(sm.tutorialType, isNull);
      });
    });

    // -------------------------------------------------------------------------
    // ResetTutorialEvent
    // -------------------------------------------------------------------------
    group('dispatch — ResetTutorialEvent', () {
      test('clears activeTutorial', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(LaunchTutorialEvent(_readingModel()));
        sm.dispatch(const ResetTutorialEvent());
        expect(sm.model.activeTutorial, isNull);
      });

      test('preserves tutorialIndex and stepIndex', () {
        final sm = TutorialOverlayStateMachine(_full);
        sm.dispatch(const ForwardTutorialEvent()); // tutorialIndex = 1
        sm.dispatch(const ResetTutorialEvent());
        expect(sm.model.tutorialIndex, 1);
        expect(sm.model.stepIndex, 0);
      });
    });

    // -------------------------------------------------------------------------
    // completedStepsOffset
    // -------------------------------------------------------------------------
    group('completedStepsOffset', () {
      test('is 0 at the start of the sequence', () {
        final sm = TutorialOverlayStateMachine(_full);
        expect(sm.completedStepsOffset, 0);
      });

      test('equals stepCount of first tutorial after advancing to second', () {
        final sm = TutorialOverlayStateMachine(_full);
        sm.dispatch(const ForwardTutorialEvent()); // → index 1
        expect(sm.completedStepsOffset, 1); // readingAssistance: 1 step
      });

      test('accumulates correctly after multiple tutorial advances', () {
        final sm = TutorialOverlayStateMachine(_full);
        sm.dispatch(
          const ForwardTutorialEvent(),
        ); // → selectModeButtons (index 1)
        sm.dispatch(const ForwardTutorialEvent()); // step 1
        sm.dispatch(const ForwardTutorialEvent()); // step 2
        sm.dispatch(const ForwardTutorialEvent()); // step 3
        sm.dispatch(const ForwardTutorialEvent()); // → writingAssistance
        expect(sm.completedStepsOffset, 5); // 1 + 4
      });

      test('returns 0 when tutorialIndex is negative', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(const BackTutorialEvent()); // tutorialIndex = -1
        expect(sm.completedStepsOffset, 0);
      });
    });

    // -------------------------------------------------------------------------
    // totalStepsInSequence
    // -------------------------------------------------------------------------
    group('totalStepsInSequence', () {
      test('returns 0 for empty sequence', () {
        expect(TutorialOverlayStateMachine([]).totalStepsInSequence, 0);
      });

      test('returns stepCount for single-tutorial sequence', () {
        expect(TutorialOverlayStateMachine(_single).totalStepsInSequence, 1);
      });

      test('returns sum of all step counts for full sequence', () {
        // 1 + 4 + 1 = 6
        expect(TutorialOverlayStateMachine(_full).totalStepsInSequence, 6);
      });
    });

    // -------------------------------------------------------------------------
    // Navigation flags
    // -------------------------------------------------------------------------
    group('navigation flags', () {
      test(
        'canGoBack / hasPreviousStep / hasPreviousTutorial are false at start',
        () {
          final sm = TutorialOverlayStateMachine(_single);
          expect(sm.canGoBack, false);
          expect(sm.hasPreviousStep, false);
          expect(sm.hasPreviousTutorial, false);
        },
      );

      test('hasPreviousStep is true after advancing a step', () {
        final sm = TutorialOverlayStateMachine(_multiStep);
        sm.dispatch(const ForwardTutorialEvent()); // step 1
        expect(sm.hasPreviousStep, true);
        expect(sm.canGoBack, true);
      });

      test(
        'hasPreviousTutorial is true after advancing to second tutorial',
        () {
          final sm = TutorialOverlayStateMachine(_full);
          sm.dispatch(const ForwardTutorialEvent()); // tutorialIndex = 1
          expect(sm.hasPreviousTutorial, true);
          expect(sm.canGoBack, true);
        },
      );

      test('hasNextStep is true for multi-step tutorial at step 0', () {
        expect(TutorialOverlayStateMachine(_multiStep).hasNextStep, true);
      });

      test('hasNextStep is false for single-step tutorial', () {
        expect(TutorialOverlayStateMachine(_single).hasNextStep, false);
      });

      test('hasNextTutorial is true when not at the last tutorial', () {
        expect(TutorialOverlayStateMachine(_full).hasNextTutorial, true);
      });

      test('hasNextTutorial is false for single-tutorial sequence', () {
        expect(TutorialOverlayStateMachine(_single).hasNextTutorial, false);
      });

      test('canGoForward is false after completing the sequence', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(const ForwardTutorialEvent()); // past end
        expect(sm.canGoForward, false);
        expect(sm.hasNextStep, false);
        expect(sm.hasNextTutorial, false);
      });
    });

    // -------------------------------------------------------------------------
    // tutorialType
    // -------------------------------------------------------------------------
    group('tutorialType', () {
      test('returns first tutorial at index 0', () {
        expect(
          TutorialOverlayStateMachine(_full).tutorialType,
          TutorialEnum.readingAssistance,
        );
      });

      test('returns correct type after advancing to next tutorial', () {
        final sm = TutorialOverlayStateMachine(_full);
        sm.dispatch(const ForwardTutorialEvent());
        expect(sm.tutorialType, TutorialEnum.selectModeButtons);
      });

      test('returns null when tutorialIndex is past end of sequence', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(const ForwardTutorialEvent());
        expect(sm.tutorialType, isNull);
      });

      test('returns null for empty sequence', () {
        expect(TutorialOverlayStateMachine([]).tutorialType, isNull);
      });

      test('returns null when tutorialIndex is negative', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(const BackTutorialEvent()); // tutorialIndex = -1
        expect(sm.tutorialType, isNull);
      });
    });

    // -------------------------------------------------------------------------
    // isTutorialActive
    // -------------------------------------------------------------------------
    group('isTutorialActive', () {
      test('returns false before any launch', () {
        final sm = TutorialOverlayStateMachine(_single);
        expect(sm.isTutorialActive(TutorialEnum.readingAssistance), false);
      });

      test('returns true for the launched tutorial type', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(LaunchTutorialEvent(_readingModel()));
        expect(sm.isTutorialActive(TutorialEnum.readingAssistance), true);
      });

      test('returns false for a different tutorial type', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(LaunchTutorialEvent(_readingModel()));
        expect(sm.isTutorialActive(TutorialEnum.selectModeButtons), false);
      });

      test('returns false after reset clears activeTutorial', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(LaunchTutorialEvent(_readingModel()));
        sm.dispatch(const ResetTutorialEvent());
        expect(sm.isTutorialActive(TutorialEnum.readingAssistance), false);
      });
    });

    // -------------------------------------------------------------------------
    // hasCompletedSequence
    // -------------------------------------------------------------------------
    group('hasCompletedSequence', () {
      test('is false at the start of a non-empty sequence', () {
        expect(
          TutorialOverlayStateMachine(_single).hasCompletedSequence,
          false,
        );
      });

      test('is true after advancing past the last tutorial', () {
        final sm = TutorialOverlayStateMachine(_single);
        sm.dispatch(
          const ForwardTutorialEvent(),
        ); // tutorialIndex = 1 >= length 1
        expect(sm.hasCompletedSequence, true);
      });

      test('is false mid-sequence', () {
        final sm = TutorialOverlayStateMachine(_full);
        sm.dispatch(const ForwardTutorialEvent()); // tutorialIndex = 1
        expect(sm.hasCompletedSequence, false);
      });

      test('is true for empty sequence (nothing left to show)', () {
        expect(TutorialOverlayStateMachine([]).hasCompletedSequence, true);
      });
    });
  });

  // ===========================================================================
  // Step declarations: the template list is the single source of the count
  // ===========================================================================
  group('step count derivation', () {
    test('every tutorial reports the length of its template list', () {
      for (final tutorial in TutorialEnum.values) {
        expect(
          tutorial.stepCount,
          tutorial.stepTemplates.length,
          reason: '$tutorial step count must derive from its templates',
        );
      }
    });

    test('no tutorial declares zero steps', () {
      for (final tutorial in TutorialEnum.values) {
        expect(tutorial.stepCount, greaterThan(0), reason: '$tutorial');
      }
    });

    test('every declared step is reachable — none is dead config', () {
      // The bug this pins: writingAssistance once declared two tooltip sizes
      // and two styles against a step count of 1, so its second step could
      // never run. Walking a model to its last step proves each has data.
      for (final tutorial in TutorialEnum.values) {
        final sm = TutorialOverlayStateMachine([tutorial]);
        final model = _model(tutorial);
        for (var i = 0; i < tutorial.stepCount; i++) {
          expect(model.targetKeysAt(i), isNotEmpty);
          expect(model.tooltipSizeAt(i), tutorial.stepTemplates[i].tooltipSize);
          if (i < tutorial.stepCount - 1) {
            sm.dispatch(const ForwardTutorialEvent());
            expect(sm.model.stepIndex, i + 1);
          }
        }
      }
    });

    test('a model cannot be built with the wrong number of steps', () {
      expect(
        () => TutorialModel(
          tutorialType: TutorialEnum.readingAssistance,
          stepsData: [_stepData(), _stepData()],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ===========================================================================
  // App-scoped controller: one sequence at a time, the rest queued
  // ===========================================================================
  group('TutorialOverlayController — sequences', () {
    const chat = [
      TutorialEnum.readingAssistance,
      TutorialEnum.selectModeButtons,
    ];
    const other = [TutorialEnum.writingAssistance];

    test('no sequence active before one is requested', () {
      final c = TutorialOverlayController(progress: const _FakeProgress());
      expect(c.hasActiveSequence, false);
      expect(c.state.tutorialType, isNull);
      // Reads safely with nothing running rather than needing a null check.
      expect(c.state.hasCompletedSequence, true);
      expect(c.isTutorialQueued(TutorialEnum.readingAssistance), false);
    });

    test('requesting a sequence arms its first enabled tutorial', () {
      final c = TutorialOverlayController(progress: const _FakeProgress());
      expect(c.requestSequence(chat), true);
      expect(c.hasActiveSequence, true);
      expect(c.state.tutorialType, TutorialEnum.readingAssistance);
    });

    test('already-seen tutorials are left out of the counter', () {
      final c = TutorialOverlayController(
        progress: const _FakeProgress(seen: {TutorialEnum.readingAssistance}),
      );
      c.requestSequence(chat);
      expect(c.state.tutorialType, TutorialEnum.selectModeButtons);
      expect(
        c.state.totalStepsInSequence,
        TutorialEnum.selectModeButtons.stepCount,
      );
    });

    test('a fully-seen sequence does not start', () {
      final c = TutorialOverlayController(
        progress: const _FakeProgress(
          seen: {
            TutorialEnum.readingAssistance,
            TutorialEnum.selectModeButtons,
          },
        ),
      );
      expect(c.requestSequence(chat), false);
      expect(c.hasActiveSequence, false);
    });

    test('resumes at the saved step', () {
      final c = TutorialOverlayController(
        progress: const _FakeProgress(
          seen: {TutorialEnum.readingAssistance},
          resumeSteps: {TutorialEnum.selectModeButtons: 2},
        ),
      );
      c.requestSequence(chat);
      expect(c.state.model.stepIndex, 2);
    });

    test('re-requesting the active sequence is a no-op', () {
      final c = TutorialOverlayController(progress: const _FakeProgress());
      c.requestSequence(chat);
      expect(c.requestSequence(chat), false);
      expect(c.state.tutorialType, TutorialEnum.readingAssistance);
    });

    test('a second sequence is queued, not dropped, and starts on release', () {
      final c = TutorialOverlayController(progress: const _FakeProgress());
      c.requestSequence(chat);
      expect(c.requestSequence(other), false);
      expect(c.state.tutorialType, TutorialEnum.readingAssistance);

      c.releaseSequence(chat);
      expect(c.hasActiveSequence, true);
      expect(c.state.tutorialType, TutorialEnum.writingAssistance);
    });

    test(
      'releasing a queued sequence removes it without disturbing the active one',
      () {
        final c = TutorialOverlayController(progress: const _FakeProgress());
        c.requestSequence(chat);
        c.requestSequence(other);
        c.releaseSequence(other);
        c.releaseSequence(chat);
        expect(c.hasActiveSequence, false);
      },
    );

    test('a queued sequence with nothing left to show is skipped on drain', () {
      final c = TutorialOverlayController(
        progress: const _FakeProgress(seen: {TutorialEnum.writingAssistance}),
      );
      c.requestSequence(chat);
      c.requestSequence(other);
      c.releaseSequence(chat);
      expect(c.hasActiveSequence, false);
    });

    test('sequence identity is by content, not list instance', () {
      final c = TutorialOverlayController(progress: const _FakeProgress());
      c.requestSequence(TutorialSequences.chatTutorialSequence);
      // A fresh list with the same tutorials is the same sequence.
      expect(c.requestSequence(TutorialSequences.chatTutorialSequence), false);
      c.releaseSequence(TutorialSequences.chatTutorialSequence);
      expect(c.hasActiveSequence, false);
    });
  });

  // ===========================================================================
  // Launcher registry: hosts declare what they own, no host-side switch
  // ===========================================================================
  group('TutorialOverlayController — launchers', () {
    const chat = [
      TutorialEnum.readingAssistance,
      TutorialEnum.selectModeButtons,
    ];

    test('the armed tutorial\'s launcher runs when the sequence starts', () {
      final calls = <TutorialEnum>[];
      final c = TutorialOverlayController(progress: const _FakeProgress());
      c.registerLauncher(TutorialEnum.readingAssistance, () async {
        calls.add(TutorialEnum.readingAssistance);
      });
      c.requestSequence(chat);
      expect(calls, [TutorialEnum.readingAssistance]);
    });

    testWidgets(
      'a host registering while its tutorial waits is the launch trigger',
      (tester) async {
        final calls = <TutorialEnum>[];
        final c = TutorialOverlayController(progress: const _FakeProgress());
        c.requestSequence(chat);
        expect(calls, isEmpty, reason: 'nothing registered yet');

        c.registerLauncher(TutorialEnum.readingAssistance, () async {
          calls.add(TutorialEnum.readingAssistance);
        });
        await tester.pump();
        expect(calls, [TutorialEnum.readingAssistance]);
      },
    );

    testWidgets(
      'registering a tutorial that is not waiting does not launch it',
      (tester) async {
        final calls = <TutorialEnum>[];
        final c = TutorialOverlayController(progress: const _FakeProgress());
        c.requestSequence(chat);
        c.registerLauncher(TutorialEnum.selectModeButtons, () async {
          calls.add(TutorialEnum.selectModeButtons);
        });
        await tester.pump();
        expect(calls, isEmpty);
      },
    );

    test('an owner wins over an opener for the same tutorial', () {
      final calls = <String>[];
      final c = TutorialOverlayController(progress: const _FakeProgress());
      c.registerLauncher(
        TutorialEnum.readingAssistance,
        () async => calls.add('opener'),
        role: TutorialLaunchRole.opener,
      );
      c.registerLauncher(
        TutorialEnum.readingAssistance,
        () async => calls.add('owner'),
      );
      c.requestSequence(chat);
      expect(calls, ['owner']);
    });

    testWidgets('an opener that mounts the owner hands off to it', (
      tester,
    ) async {
      final calls = <String>[];
      final c = TutorialOverlayController(progress: const _FakeProgress());
      // The opener's whole job: make the owner exist. Mirrors the chat opening
      // its toolbar so SelectModeButtons can mount.
      c.registerLauncher(TutorialEnum.readingAssistance, () async {
        calls.add('opener');
        c.registerLauncher(
          TutorialEnum.readingAssistance,
          () async => calls.add('owner'),
        );
      }, role: TutorialLaunchRole.opener);
      c.requestSequence(chat);
      await tester.pump();
      expect(calls, ['opener', 'owner']);
    });

    testWidgets(
      'the owner mounting mid-preparation does not launch underneath it',
      (tester) async {
        final calls = <String>[];
        final c = TutorialOverlayController(progress: const _FakeProgress());
        c.registerLauncher(TutorialEnum.readingAssistance, () async {
          c.registerLauncher(
            TutorialEnum.readingAssistance,
            () async => calls.add('owner'),
          );
          // Preparation continues after the owner mounts; the owner must wait.
          await Future<void>.microtask(() {});
          calls.add('opener-done');
        }, role: TutorialLaunchRole.opener);
        c.requestSequence(chat);
        await tester.pump();
        expect(calls, ['opener-done', 'owner']);
      },
    );

    test('unregistering falls back to the opener', () {
      final calls = <String>[];
      final c = TutorialOverlayController(progress: const _FakeProgress());
      c.registerLauncher(
        TutorialEnum.readingAssistance,
        () async => calls.add('opener'),
        role: TutorialLaunchRole.opener,
      );
      c.registerLauncher(
        TutorialEnum.readingAssistance,
        () async => calls.add('owner'),
      );
      c.unregisterLauncher(TutorialEnum.readingAssistance);
      c.requestSequence(chat);
      expect(calls, ['opener']);
    });

    test(
      'a sequence with no registered host stays armed rather than failing',
      () {
        final c = TutorialOverlayController(progress: const _FakeProgress());
        expect(c.requestSequence(chat), true);
        expect(c.state.tutorialType, TutorialEnum.readingAssistance);
        expect(c.state.model.activeTutorial, isNull);
      },
    );
  });
}
