import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The catalog of sequences a host can request. Which of a sequence's tutorials
/// this learner still needs is decided by the controller — see
/// [TutorialProgressSource].
class TutorialSequences {
  /// The greeting, then the world map itself. [TutorialEnum.welcome] is
  /// prepended to both orientation sequences and simply drops out of the second
  /// one the learner reaches, because a sequence is built over only the
  /// tutorials they have not seen — which is the whole once-ever mechanism.
  static TutorialSequence get worldOrientationSequence => [
    TutorialEnum.welcome,
    TutorialEnum.worldMap,
  ];

  /// The greeting, then the course plan. [TutorialEnum.welcome] is shared with
  /// [worldOrientationSequence] and drops out of whichever the learner reaches
  /// second, so nobody is greeted twice.
  static TutorialSequence get courseOrientationSequence => [
    TutorialEnum.welcome,
    TutorialEnum.coursePlan,
  ];

  /// Offered after the learner's first finished activity. Alone in its sequence:
  /// it is one tutorial that walks the whole app.
  static TutorialSequence get appTourSequence => [TutorialEnum.appTour];

  /// The goal header, once the activity chat is actually running.
  static TutorialSequence get activityGoalsSequence => [
    TutorialEnum.activityGoals,
  ];

  static TutorialSequence get chatTutorialSequence => [
    TutorialEnum.readingAssistance,
    TutorialEnum.selectModeButtons,
    TutorialEnum.writingAssistance,
  ];

  /// The open-sessions list, the first time the learner is looking at one.
  static TutorialSequence get openSessionsSequence => [
    TutorialEnum.openSessions,
  ];

  /// The role-card grid, the first time the learner is picking a role.
  static TutorialSequence get activityRolesSequence => [
    TutorialEnum.activityRoles,
  ];
}

/// Sequence-level presentation: the display title under the card's progress
/// bar, beside the sequence-wide Skip control every card carries. Attached
/// to the sequence rather than the tutorial because both describe the *run*
/// the learner is walking — two sequences share [TutorialEnum.welcome], and a
/// run's identity survives the seen-filter dropping tutorials out of it.
enum TutorialSequenceKind {
  worldOrientation,
  courseOrientation,
  appTour,
  activityGoals,
  chat,
  openSessions,
  activityRoles;

  String title(L10n l10n) => switch (this) {
    TutorialSequenceKind.worldOrientation =>
      l10n.tutorialSequenceTitleWorldOrientation,
    TutorialSequenceKind.courseOrientation =>
      l10n.tutorialSequenceTitleCourseOrientation,
    TutorialSequenceKind.appTour => l10n.tutorialSequenceTitleAppTour,
    TutorialSequenceKind.activityGoals =>
      l10n.tutorialSequenceTitleActivityGoals,
    TutorialSequenceKind.chat => l10n.tutorialSequenceTitleChat,
    TutorialSequenceKind.openSessions => l10n.tutorialSequenceTitleOpenSessions,
    TutorialSequenceKind.activityRoles =>
      l10n.tutorialSequenceTitleActivityRoles,
  };

  TutorialSequence get sequence => switch (this) {
    TutorialSequenceKind.worldOrientation =>
      TutorialSequences.worldOrientationSequence,
    TutorialSequenceKind.courseOrientation =>
      TutorialSequences.courseOrientationSequence,
    TutorialSequenceKind.appTour => TutorialSequences.appTourSequence,
    TutorialSequenceKind.activityGoals =>
      TutorialSequences.activityGoalsSequence,
    TutorialSequenceKind.chat => TutorialSequences.chatTutorialSequence,
    TutorialSequenceKind.openSessions => TutorialSequences.openSessionsSequence,
    TutorialSequenceKind.activityRoles =>
      TutorialSequences.activityRolesSequence,
  };

  /// The kind of [sequence], matched by content against the catalog — the
  /// controller holds the requested tutorial list, not a kind, so identity is
  /// recovered rather than threaded through. Matched against the *requested*
  /// (unfiltered) sequence: the seen-filter runs after the request. An ad-hoc
  /// sequence (a test's) matches nothing — no title, no skip.
  static TutorialSequenceKind? of(TutorialSequence? sequence) {
    if (sequence == null) return null;
    for (final kind in values) {
      if (listEquals(kind.sequence, sequence)) return kind;
    }
    return null;
  }
}

/// What the controller reads to decide which tutorials a learner still needs
/// and where each resumes. Backed by the learner's profile in the app; a
/// subclass stands in for it in tests, so the sequence and queue logic is
/// testable without a live user.
class TutorialProgressSource {
  const TutorialProgressSource();

  bool isEnabled(TutorialEnum tutorial) => tutorial.globallyEnabled;

  int resumeStep(TutorialEnum tutorial) => tutorial.stepProgress;

  /// Persists [tutorial]'s resume step — or, at its step count, marks it seen.
  /// On the source rather than called on the enum directly so the controller's
  /// writes go through the same seam its reads do, and tests observe both.
  void saveProgress(TutorialEnum tutorial, int stepIndex) =>
      tutorial.saveProgress(stepIndex);
}
