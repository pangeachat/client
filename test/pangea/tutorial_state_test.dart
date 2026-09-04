import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/tutorials/tutorial_copy.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_controller.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_state_machine.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/features/tutorials/tutorial_state_transition_events.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';

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

  /// Records what the controller persisted, when observing writes matters.
  /// A tutorial saved at its step count was marked seen.
  final Map<TutorialEnum, int>? progressLog;

  const _FakeProgress({
    this.seen = const {},
    this.resumeSteps = const {},
    this.progressLog,
  });

  @override
  bool isEnabled(TutorialEnum tutorial) => !seen.contains(tutorial);

  @override
  int resumeStep(TutorialEnum tutorial) => resumeSteps[tutorial] ?? 0;

  @override
  void saveProgress(TutorialEnum tutorial, int stepIndex) =>
      progressLog?[tutorial] = stepIndex;
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
          expect(model.dataAt(i), isNotNull);
          expect(tutorial.stepTemplates[i].tooltipSize, isNotNull);
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

    testWidgets(
      'a second sequence is queued, not dropped, and starts on release',
      (tester) async {
        final c = TutorialOverlayController(progress: const _FakeProgress());
        c.requestSequence(chat);
        expect(c.requestSequence(other), false);
        expect(c.state.tutorialType, TutorialEnum.readingAssistance);

        c.releaseSequence(chat);
        // The drain is deferred until the ending sequence's overlay close has run,
        // so the next one never reuses an entry that is about to be removed.
        expect(c.hasActiveSequence, false, reason: 'drain waits for the frame');
        await tester.pump();
        expect(c.hasActiveSequence, true);
        expect(c.state.tutorialType, TutorialEnum.writingAssistance);
      },
    );

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

    testWidgets(
      'a queued sequence with nothing left to show is skipped on drain',
      (tester) async {
        final c = TutorialOverlayController(
          progress: const _FakeProgress(seen: {TutorialEnum.writingAssistance}),
        );
        c.requestSequence(chat);
        c.requestSequence(other);
        c.releaseSequence(chat);
        await tester.pump();
        expect(c.hasActiveSequence, false);
      },
    );

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
  // Skip: the learner opts out of the WHOLE running sequence, not one card
  // ===========================================================================
  group('TutorialOverlayController — skipCurrentSequence', () {
    test('marks every unseen tutorial in the requested sequence seen', () {
      final log = <TutorialEnum, int>{};
      final c = TutorialOverlayController(
        progress: _FakeProgress(progressLog: log),
      );
      c.requestSequence(_full);
      c.skipCurrentSequence();
      // Each saved at its step count — that is what marks it seen.
      expect(log, {
        TutorialEnum.readingAssistance:
            TutorialEnum.readingAssistance.stepCount,
        TutorialEnum.selectModeButtons:
            TutorialEnum.selectModeButtons.stepCount,
        TutorialEnum.writingAssistance:
            TutorialEnum.writingAssistance.stepCount,
      });
      expect(c.hasActiveSequence, false);
    });

    test(
      'skips the tutorials still to come, not only the one showing — the bug '
      'this pins: marking only the current one partially re-offered the same '
      'walkthrough on the next trigger',
      () {
        final log = <TutorialEnum, int>{};
        final c = TutorialOverlayController(
          progress: _FakeProgress(progressLog: log),
        );
        c.requestSequence(_full);
        expect(c.state.tutorialType, TutorialEnum.readingAssistance);
        c.skipCurrentSequence();
        expect(log.containsKey(TutorialEnum.selectModeButtons), true);
        expect(log.containsKey(TutorialEnum.writingAssistance), true);
      },
    );

    test('already-seen tutorials in the sequence are not re-marked', () {
      final log = <TutorialEnum, int>{};
      final c = TutorialOverlayController(
        progress: _FakeProgress(
          seen: {TutorialEnum.readingAssistance},
          progressLog: log,
        ),
      );
      c.requestSequence(_full);
      c.skipCurrentSequence();
      expect(log.containsKey(TutorialEnum.readingAssistance), false);
      expect(log.containsKey(TutorialEnum.selectModeButtons), true);
      expect(log.containsKey(TutorialEnum.writingAssistance), true);
    });

    testWidgets('a queued sequence still starts after a skip', (tester) async {
      final c = TutorialOverlayController(
        progress: _FakeProgress(progressLog: {}),
      );
      c.requestSequence(_full);
      c.requestSequence(const [TutorialEnum.appTour]);
      c.skipCurrentSequence();
      await tester.pump();
      expect(c.state.tutorialType, TutorialEnum.appTour);
    });

    test('a skip with nothing running is a no-op', () {
      final log = <TutorialEnum, int>{};
      final c = TutorialOverlayController(
        progress: _FakeProgress(progressLog: log),
      );
      c.skipCurrentSequence();
      expect(log, isEmpty);
    });
  });

  // ===========================================================================
  // Sequence identity: the card's title and Skip control come from the kind
  // ===========================================================================
  group('TutorialSequenceKind', () {
    test('matches every catalog sequence by content', () {
      for (final kind in TutorialSequenceKind.values) {
        expect(TutorialSequenceKind.of(kind.sequence), kind);
      }
    });

    test('matches a fresh list with the same tutorials — content, not '
        'instance, because the controller holds the requested list', () {
      expect(
        TutorialSequenceKind.of([TutorialEnum.welcome, TutorialEnum.worldMap]),
        TutorialSequenceKind.worldOrientation,
      );
    });

    test('an ad-hoc sequence matches nothing — no title, no skip', () {
      expect(TutorialSequenceKind.of(_single), isNull);
      expect(TutorialSequenceKind.of(null), isNull);
    });

    test('activeSequenceKind names the running sequence', () {
      final c = TutorialOverlayController(progress: const _FakeProgress());
      expect(c.activeSequenceKind, isNull);
      c.requestSequence(TutorialSequences.chatTutorialSequence);
      expect(c.activeSequenceKind, TutorialSequenceKind.chat);
    });

    test('activeSequenceKind survives the seen-filter dropping a tutorial — '
        'identity is the REQUESTED sequence, not the filtered one', () {
      final c = TutorialOverlayController(
        progress: const _FakeProgress(seen: {TutorialEnum.welcome}),
      );
      c.requestSequence(TutorialSequences.worldOrientationSequence);
      expect(c.state.tutorialType, TutorialEnum.worldMap);
      expect(c.activeSequenceKind, TutorialSequenceKind.worldOrientation);
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
      Future<void> opener() async => calls.add('opener');
      Future<void> owner() async => calls.add('owner');
      c.registerLauncher(
        TutorialEnum.readingAssistance,
        opener,
        role: TutorialLaunchRole.opener,
      );
      c.registerLauncher(TutorialEnum.readingAssistance, owner);
      c.unregisterLauncher(TutorialEnum.readingAssistance, owner);
      c.requestSequence(chat);
      expect(calls, ['opener']);
    });

    test('unregistering a launcher that was replaced leaves the new one', () {
      // Two hosts can own the same tutorial at different times (the greeting
      // fires on the map or a course plan). The one that left must not take the
      // current registration with it.
      final calls = <String>[];
      final c = TutorialOverlayController(progress: const _FakeProgress());
      Future<void> first() async => calls.add('first');
      Future<void> second() async => calls.add('second');
      c.registerLauncher(TutorialEnum.readingAssistance, first);
      c.registerLauncher(TutorialEnum.readingAssistance, second);
      c.unregisterLauncher(TutorialEnum.readingAssistance, first);
      c.requestSequence(chat);
      expect(calls, ['second']);
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
  // ===========================================================================
  // The welcome greeting: shown as a vocabulary word when we resolved a real
  // L2 one, as plain text otherwise. See tutorials.instructions.md.
  // ===========================================================================
  group('soleLemmaToken', () {
    PangeaToken token(String content, String pos) => PangeaToken(
      text: PangeaTokenText(
        content: content,
        length: content.length,
        offset: 0,
      ),
      lemma: Lemma(text: content, saveVocab: true, form: content),
      pos: pos,
      morph: const {},
    );

    test('a bare word is the word', () {
      expect(
        soleLemmaToken([token('Welcome', 'intj')])?.text.content,
        'Welcome',
      );
    });

    test(
      "punctuation around the word is ignored — the regression: the greeting "
      "carries its language's own marks, and counting raw tokens rejected "
      'every punctuated greeting',
      () {
        final tokens = [
          token('¡', 'punct'),
          token('Bienvenido', 'intj'),
          token('!', 'punct'),
        ];
        expect(soleLemmaToken(tokens)?.text.content, 'Bienvenido');
      },
    );

    test('a trailing mark after a space is ignored too (French)', () {
      final tokens = [token('Bonjour', 'intj'), token('!', 'punct')];
      expect(soleLemmaToken(tokens)?.text.content, 'Bonjour');
    });

    test('two real words is ambiguous — no word card rather than a guess', () {
      final tokens = [token('Buenos', 'adj'), token('días', 'noun')];
      expect(soleLemmaToken(tokens), isNull);
    });

    test('nothing but punctuation resolves to no word', () {
      expect(soleLemmaToken([token('!', 'punct')]), isNull);
      expect(soleLemmaToken([]), isNull);
    });
  });

  group('TutorialGreeting', () {
    PangeaToken token() => PangeaToken(
      text: PangeaTokenText(content: 'Bienvenido', length: 10, offset: 0),
      lemma: Lemma(text: 'bienvenido', saveVocab: true, form: 'Bienvenido'),
      // What a greeting actually tags as. A function word, so it will never be
      // reported "new" — the bubble still renders, just without the green.
      pos: 'intj',
      morph: const {},
    );

    test('a tokenized L2 greeting is a bubble', () {
      final greeting = TutorialGreeting(
        'Bienvenido',
        token: token(),
        langCode: 'es',
      );
      expect(greeting.isBubble, isTrue);
    });

    test('a greeting with no token is not a bubble — the fallback paths leave '
        'the word in a language the learner already speaks', () {
      expect(const TutorialGreeting('Welcome').isBubble, isFalse);
    });

    test('a token with no language is not a bubble', () {
      expect(TutorialGreeting('Bienvenido', token: token()).isBubble, isFalse);
    });
  });

  group('TutorialModel.welcome', () {
    test('a tokenized L2 greeting is carried as a bubble', () {
      final greeting = TutorialGreeting(
        'Bienvenido',
        token: PangeaToken(
          text: PangeaTokenText(content: 'Bienvenido', length: 10, offset: 0),
          lemma: Lemma(text: 'bienvenido', saveVocab: true, form: 'Bienvenido'),
          pos: 'intj',
          morph: const {},
        ),
        langCode: 'es',
      );
      final data = TutorialModel.welcome(greeting).dataAt(0);
      expect(data.wordBubble!()!.isBubble, isTrue);
    });

    test('a greeting that could not be tokenized is carried as plain text', () {
      final data = TutorialModel.welcome(
        const TutorialGreeting('Welcome'),
      ).dataAt(0);
      expect(data.wordBubble!()!.isBubble, isFalse);
    });

    test('the copy takes NO runtime arguments — the word is shown above the '
        'sentence, never spliced into it, so no word order is assumed', () {
      final data = TutorialModel.welcome(
        const TutorialGreeting('Welcome'),
      ).dataAt(0);
      expect(data.resolvedTooltipArgs, isEmpty);
    });

    test('the greeting step carries no target and needs no host state', () {
      final data = TutorialModel.welcome(
        const TutorialGreeting('Welcome'),
      ).dataAt(0);
      expect(data.hasSpotlight, isFalse);
      expect(data.isArmed, isFalse);
      expect(data.canShowNextStep(), isTrue);
    });
  });

  // ===========================================================================
  // Which armed steps may be put back on screen
  // ===========================================================================
  group('the scrim, and which steps withhold it', () {
    // Only ONE step drops the scrim now, and only for a visual reason: the map
    // introduction is about the whole screen, so darkening the screen works
    // against it. It still advances on a tap like any other step.
    //
    // The pin step used to drop it too, because it shimmered every two-role pin
    // and a cut-out could not match an 8px dot. Pointing at ONE activity, at a
    // guaranteed mid tier, with a padded circular hole, removed that reason —
    // and with it the whole shimmer path and the undimmed-armed step kind.
    test('the map introduction is the one step without a scrim', () {
      expect(TutorialEnum.worldMap.stepTemplates.first.dimsBackground, isFalse);
      for (final tutorial in TutorialEnum.values) {
        for (var i = 0; i < tutorial.stepCount; i++) {
          final expected = !(tutorial == TutorialEnum.worldMap && i == 0);
          expect(
            tutorial.stepTemplates[i].dimsBackground,
            expected,
            reason: '$tutorial step $i',
          );
        }
      }
    });

    test('the pin step lights something, so it keeps its scrim', () {
      expect(TutorialEnum.worldMap.stepTemplates.last.dimsBackground, isTrue);
    });

    test('the course plan keeps its scrim throughout — every one of its steps '
        'lights something, so there is something to cut out of', () {
      for (final template in TutorialEnum.coursePlan.stepTemplates) {
        expect(template.dimsBackground, isTrue);
      }
    });
  });
}
