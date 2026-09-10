import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_templates.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum TutorialEnum {
  readingAssistance,
  writingAssistance,
  selectModeButtons,
  welcome(isOrientation: true),
  worldMap(isOrientation: true),
  activityGoals(isOrientation: true),
  coursePlan(isOrientation: true),
  appTour(isOrientation: true),
  openSessions(isOrientation: true),
  activityRoles(isOrientation: true);

  /// Orientation tutorials teach the app itself — where things are, what to do
  /// first — so they are exempt from the subscription gate: a learner who
  /// cannot find their way around will not convert. Feature tutorials teach
  /// paid AI tools and stay gated. See tutorials.instructions.md.
  final bool isOrientation;

  const TutorialEnum({this.isOrientation = false});

  /// This tutorial's steps, in order. The single declaration of what the
  /// tutorial says and how many steps it has.
  List<TutorialStepTemplate> get stepTemplates => switch (this) {
    TutorialEnum.readingAssistance => TutorialStepTemplates.readingAssistance,
    TutorialEnum.writingAssistance => TutorialStepTemplates.writingAssistance,
    TutorialEnum.selectModeButtons => TutorialStepTemplates.selectModeButtons,
    TutorialEnum.welcome => TutorialStepTemplates.welcome,
    TutorialEnum.worldMap => TutorialStepTemplates.worldMap,
    TutorialEnum.activityGoals => TutorialStepTemplates.activityGoals,
    TutorialEnum.coursePlan => TutorialStepTemplates.coursePlan,
    TutorialEnum.appTour => TutorialStepTemplates.appTour,
    TutorialEnum.openSessions => TutorialStepTemplates.openSessions,
    TutorialEnum.activityRoles => TutorialStepTemplates.activityRoles,
  };

  int get stepCount => stepTemplates.length;

  bool get globallyEnabled {
    if (!isOrientation &&
        !MatrixState
            .pangeaController
            .subscriptionController
            .showSubscriptionGatedContent) {
      return false;
    }

    return !_hasBeenSeen && stepProgress < stepCount;
  }

  InstructionsEnum get _instructionsEnum => switch (this) {
    TutorialEnum.readingAssistance =>
      InstructionsEnum.readingAssistanceTutorial,
    TutorialEnum.writingAssistance =>
      InstructionsEnum.writingAssistanceTutorial,
    TutorialEnum.selectModeButtons =>
      InstructionsEnum.selectModeButtonsTutorial,
    TutorialEnum.welcome => InstructionsEnum.welcomeTutorial,
    TutorialEnum.worldMap => InstructionsEnum.worldMapTutorial,
    TutorialEnum.activityGoals => InstructionsEnum.activityGoalsTutorial,
    TutorialEnum.coursePlan => InstructionsEnum.coursePlanTutorial,
    TutorialEnum.appTour => InstructionsEnum.appTourTutorial,
    TutorialEnum.openSessions => InstructionsEnum.openSessionsTutorial,
    TutorialEnum.activityRoles => InstructionsEnum.activityRolesTutorial,
  };

  bool get _hasBeenSeen => _instructionsEnum.isToggledOff;

  void _markSeen() {
    _instructionsEnum.setToggledOff(true);
    _instructionsEnum.clearStepProgress();
  }

  /// The step index to resume from on the next launch of this tutorial.
  /// Returns 0 if no progress has been saved yet.
  int get stepProgress => _instructionsEnum.stepProgress;

  /// Persists [stepIndex] so the user can resume mid-tutorial on the next
  /// launch. Called after each successful step advance in the overlay widget.
  void saveProgress(int stepIndex) {
    if (stepIndex >= stepCount) {
      _markSeen();
      return;
    }
    _instructionsEnum.setStepProgress(stepIndex);
  }

  /// Marks every not-yet-seen tutorial in [tutorials] seen, in ONE profile
  /// write — a backfill of several flags must not fan out a network save per
  /// flag. A no-op when none is pending, so it is safe to run every session.
  static Future<void> markSeen(List<TutorialEnum> tutorials) async {
    final pending = tutorials.where((t) => t.globallyEnabled).toList();
    if (pending.isEmpty) return;
    await MatrixState.pangeaController.userController.updateProfile((profile) {
      for (final tutorial in pending) {
        profile.instructionSettings.setStatus(tutorial._instructionsEnum, true);
        profile.instructionSettings.clearStepProgress(
          tutorial._instructionsEnum,
        );
      }
      return profile;
    });
  }
}
