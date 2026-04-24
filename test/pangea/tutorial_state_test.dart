import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/onboarding/tutorial_enum.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay_controller.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_state_transition_events.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_step_model.dart';

// Sequences used across tests.
// readingAssistance: 1 step  |  selectModeButtons: 3 steps  |  writingAssistance: 1 step
const _single = [TutorialEnum.readingAssistance];
const _multiStep = [TutorialEnum.selectModeButtons];
const _full = [
  TutorialEnum.readingAssistance,
  TutorialEnum.selectModeButtons,
  TutorialEnum.writingAssistance,
];

TutorialStepData _stepData() => TutorialStepData(targetKey: 'test_key');

ReadingAssistantTutorialModel _readingModel() =>
    ReadingAssistantTutorialModel(data: [_stepData()]);

SelectModeButtonsTutorialModel _selectModel() =>
    SelectModeButtonsTutorialModel(data: List.generate(3, (_) => _stepData()));

void main() {
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
        'goes back to last step (index 2) of a 3-step previous tutorial',
        () {
          final sm = TutorialOverlayStateMachine(_full);
          // Advance through selectModeButtons into writingAssistance
          sm.dispatch(const ForwardTutorialEvent()); // → selectModeButtons
          sm.dispatch(const ForwardTutorialEvent()); // step 1
          sm.dispatch(const ForwardTutorialEvent()); // step 2
          sm.dispatch(
            const ForwardTutorialEvent(),
          ); // → writingAssistance (index 2)
          sm.dispatch(const BackTutorialEvent()); // ← selectModeButtons step 2
          expect(sm.model.tutorialIndex, 1);
          expect(sm.model.stepIndex, 2);
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
        sm.dispatch(
          const ForwardTutorialEvent(),
        ); // → writingAssistance (index 2)
        expect(sm.completedStepsOffset, 4); // 1 + 3
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
        // 1 + 3 + 1 = 5
        expect(TutorialOverlayStateMachine(_full).totalStepsInSequence, 5);
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
}
