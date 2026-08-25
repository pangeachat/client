import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';

/// The one declaration of every tutorial's steps: their copy, tooltip size,
/// and spotlight geometry, in order. A tutorial's step count is the length of
/// its list here ([TutorialEnum.stepCount] reads it), so adding or removing a
/// step is a single edit and cannot leave a step unreachable.
class TutorialStepTemplates {
  static const Size _standard = Size(250, 120);

  static final List<TutorialStepTemplate> readingAssistance = [
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.readingAssistanceTutorialClickMessage,
      tooltipSize: _standard,
      borderRadius: AppConfig.borderRadius,
    ),
  ];

  static final List<TutorialStepTemplate> writingAssistance = [
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.writingAssistanceTutorialInputBar,
      tooltipSize: const Size(300, 140),
      borderRadius: 24.0,
    ),
  ];

  /// One step, no target: a message about the app rather than about anything on
  /// screen, so it centers over the darkened map or course plan.
  static final List<TutorialStepTemplate> welcome = [
    TutorialStepTemplate(
      // args: [greeting in the learner's target language]
      tooltip: (l10n, args) => l10n.tutorialWelcome(args.first),
      tooltipSize: const Size(280, 130),
    ),
  ];

  static final List<TutorialStepTemplate> worldMap = [
    TutorialStepTemplate(
      // args: [the learner's target language name]
      tooltip: (l10n, args) => l10n.tutorialWorldMapIntro(args.first),
      tooltipSize: const Size(280, 130),
    ),
    TutorialStepTemplate(
      // Both strings live here, not at the call site; the host only signals
      // which case applies by passing an arg or not.
      tooltip: (l10n, args) => args.isEmpty
          ? l10n.tutorialWorldMapPickActivity
          : l10n.tutorialWorldMapNoActivities,
      tooltipSize: const Size(280, 120),
    ),
  ];

  /// The waiting room: the learner holds a role and needs to know they are not
  /// stuck waiting for someone. Playtesters repeatedly asked whether the app
  /// could be used with other people, and this is the first moment the answer is
  /// concrete.
  static final List<TutorialStepTemplate> activityInvite = [
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialActivityInvite,
      tooltipSize: const Size(280, 120),
      borderRadius: 24.0,
      padding: 4.0,
    ),
  ];

  /// One step, one tap: it ends with the goal list open, so the learner is
  /// looking at the goals they are about to play for.
  static final List<TutorialStepTemplate> activityGoals = [
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialActivityGoals,
      tooltipSize: const Size(290, 140),
      borderRadius: AppConfig.borderRadius,
      padding: 4.0,
    ),
  ];

  static final List<TutorialStepTemplate> selectModeButtons = [
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.readingAssistanceTutorialCollectToken,
      tooltipSize: _standard,
      borderRadius: 8.0,
      padding: 4.0,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.selectModeTutorialTranslate,
      tooltipSize: _standard,
      borderRadius: 100.0,
      padding: 0.0,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.selectModeTutorialAudio,
      tooltipSize: _standard,
      borderRadius: 100.0,
      padding: 0.0,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.selectModeTutorialExit,
      tooltipSize: _standard,
      borderRadius: AppConfig.borderRadius,
    ),
  ];
}
