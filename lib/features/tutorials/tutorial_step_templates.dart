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
      // Hands the map over: no scrim and no cut-outs, because the map itself
      // carries the emphasis — it shimmers the pins this step is talking about.
      dimsBackground: false,
    ),
  ];

  /// Six steps: the offer, then one per destination. The offer counts, so the
  /// tour reads 1/6 through 6/6 — naming its length up front is honest, and a
  /// display total that differed from the real step count would reintroduce the
  /// drift one step declaration removes.
  ///
  /// It ends on **World** so that a learner who arrived by course code and has
  /// never opened the map is handed to it, where [worldMap] picks up.
  static final List<TutorialStepTemplate> appTour = [
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialAppTourOffer,
      // Taller than the other steps: this one carries its two answers inside
      // the card as well as the text and progress row.
      tooltipSize: const Size(300, 200),
      choices: [
        TutorialStepChoice(
          label: (l10n) => l10n.tutorialAppTourAccept,
          outcome: TutorialChoiceOutcome.advance,
        ),
        TutorialStepChoice(
          label: (l10n) => l10n.tutorialAppTourDecline,
          outcome: TutorialChoiceOutcome.decline,
        ),
      ],
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialAppTourChats,
      tooltipSize: const Size(270, 130),
      borderRadius: 12.0,
      padding: 4.0,
    ),
    TutorialStepTemplate(
      // args: non-empty when the learner has already joined a course.
      tooltip: (l10n, args) => args.isEmpty
          ? l10n.tutorialAppTourCoursesNone
          : l10n.tutorialAppTourCoursesSome,
      tooltipSize: const Size(270, 130),
      borderRadius: 12.0,
      padding: 4.0,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialAppTourAnalytics,
      tooltipSize: const Size(270, 130),
      borderRadius: 100.0,
      padding: 4.0,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialAppTourPractice,
      tooltipSize: const Size(280, 140),
      borderRadius: 20.0,
      padding: 4.0,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialAppTourWorld,
      tooltipSize: const Size(270, 130),
      borderRadius: 12.0,
      padding: 4.0,
    ),
  ];

  /// Mirrors [worldMap]: an introduction to the surface, then "go start one".
  static final List<TutorialStepTemplate> coursePlan = [
    TutorialStepTemplate(
      // args: [the course's name]
      tooltip: (l10n, args) => l10n.tutorialCoursePlanIntro(args.first),
      tooltipSize: const Size(290, 150),
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialCoursePlanProgress,
      tooltipSize: const Size(280, 120),
      borderRadius: AppConfig.borderRadius,
      padding: 6.0,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, args) => args.isEmpty
          ? l10n.tutorialCoursePlanPickActivity
          : l10n.tutorialCoursePlanNoActivities,
      tooltipSize: const Size(280, 120),
      borderRadius: AppConfig.borderRadius,
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
