import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';

/// The one declaration of every tutorial's steps: their copy, tooltip size,
/// and spotlight geometry, in order. A tutorial's step count is the length of
/// its list here ([TutorialEnum.stepCount] reads it), so adding or removing a
/// step is a single edit and cannot leave a step unreachable.
class TutorialStepTemplates {
  static const Size _standard = Size(250, 150);

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
      tooltipSize: const Size(300, 170),
      borderRadius: 24.0,
    ),
  ];

  /// One step, no target: a message about the app rather than about anything on
  /// screen, so it centers over the darkened map or course plan.
  ///
  /// The L2 greeting is NOT part of this string. It is displayed above it, as a
  /// word in its own right — see [TutorialStepData.wordBubble]. Splicing it into
  /// the sentence made the copy hostage to English word order: a translator
  /// whose language does not open with the greeting, or inflects around it, had
  /// nowhere to put it. Taller than the other one-step cards to make room for
  /// the word above the text.
  static final List<TutorialStepTemplate> welcome = [
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialWelcome,
      tooltipSize: const Size(280, 200),
    ),
  ];

  static final List<TutorialStepTemplate> worldMap = [
    TutorialStepTemplate(
      // args: [the learner's target language name]
      tooltip: (l10n, args) => l10n.tutorialWorldMapIntro(args.first),
      tooltipSize: const Size(280, 160),
      // No scrim: this step is about the whole screen, so darkening the thing
      // it is describing works against it. Nothing is lit either, so the card
      // takes the bottom of the screen. A tap anywhere still advances —
      // withholding the scrim is a visual decision, not a handover.
      dimsBackground: false,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialWorldMapPickActivity,
      tooltipSize: const Size(280, 160),
      // A plain rounded rect around the pin, like every other spotlight step.
      // The rect is the pin's REAL geometry for the tier it drew at — the map
      // publishes it — so a little padding is all that is needed to frame it.
      borderRadius: AppConfig.borderRadius,
      padding: 8.0,
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
      tooltipSize: const Size(300, 230),
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
      tooltipSize: const Size(270, 160),
      borderRadius: 12.0,
      padding: 4.0,
    ),
    TutorialStepTemplate(
      // args: non-empty when the learner has already joined a course.
      tooltip: (l10n, args) => args.isEmpty
          ? l10n.tutorialAppTourCoursesNone
          : l10n.tutorialAppTourCoursesSome,
      tooltipSize: const Size(270, 160),
      borderRadius: 12.0,
      padding: 4.0,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialAppTourAnalytics,
      tooltipSize: const Size(270, 160),
      borderRadius: 100.0,
      padding: 4.0,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialAppTourPractice,
      tooltipSize: const Size(280, 170),
      borderRadius: 20.0,
      padding: 4.0,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialAppTourWorld,
      tooltipSize: const Size(270, 160),
      borderRadius: 12.0,
      padding: 4.0,
    ),
  ];

  /// Mirrors [worldMap]: an introduction to the surface, then "go start one".
  static final List<TutorialStepTemplate> coursePlan = [
    TutorialStepTemplate(
      // args: [the course's name]
      tooltip: (l10n, args) => l10n.tutorialCoursePlanIntro(args.first),
      tooltipSize: const Size(290, 180),
      // Lights the whole course panel, so the cut-out follows the panel's own
      // corners. A full-height target leaves no room above or below it, so the
      // placement rule seats the card at the bottom OF THE PANEL, centred on it.
      borderRadius: AppConfig.borderRadius,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialCoursePlanProgress,
      tooltipSize: const Size(280, 150),
      borderRadius: AppConfig.borderRadius,
      padding: 6.0,
    ),
    TutorialStepTemplate(
      tooltip: (l10n, args) => args.isEmpty
          ? l10n.tutorialCoursePlanPickActivity
          : l10n.tutorialCoursePlanNoActivities,
      tooltipSize: const Size(280, 150),
      borderRadius: AppConfig.borderRadius,
      padding: 4.0,
    ),
  ];

  /// One step, one tap: it ends with the goal list open, so the learner is
  /// looking at the goals they are about to play for.
  static final List<TutorialStepTemplate> activityGoals = [
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialActivityGoals,
      tooltipSize: const Size(290, 170),
      borderRadius: AppConfig.borderRadius,
      padding: 4.0,
    ),
  ];

  /// One step: the open-sessions list on the start page's Join subpage — what
  /// a live session is, and that the humans in it may not answer right away.
  static final List<TutorialStepTemplate> openSessions = [
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialOpenSessions,
      // Taller than standard: the copy runs long, and a card that scrolls its
      // own sentence reads as broken.
      tooltipSize: const Size(300, 190),
      borderRadius: AppConfig.borderRadius,
      padding: 4.0,
    ),
  ];

  /// One step: the role-card grid the first time the learner is picking a
  /// role — what a role is, and that they choose who to act as.
  static final List<TutorialStepTemplate> activityRoles = [
    TutorialStepTemplate(
      tooltip: (l10n, _) => l10n.tutorialActivityRoles,
      // Same long-copy sizing as [openSessions].
      tooltipSize: const Size(300, 190),
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
