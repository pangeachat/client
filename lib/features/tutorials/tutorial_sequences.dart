import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';

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

  /// Separate sequences, not one two-step tutorial, because their two surfaces
  /// are owned by different hosts and a learner joining an already-running
  /// session never sees the waiting room at all. Independent sequences let that
  /// one simply not fire, instead of stalling a shared sequence behind a step
  /// whose screen never appears.
  static TutorialSequence get activityInviteSequence => [
    TutorialEnum.activityInvite,
  ];

  static TutorialSequence get activityGoalsSequence => [
    TutorialEnum.activityGoals,
  ];

  static TutorialSequence get chatTutorialSequence => [
    TutorialEnum.readingAssistance,
    TutorialEnum.selectModeButtons,
    TutorialEnum.writingAssistance,
  ];
}

/// What the controller reads to decide which tutorials a learner still needs
/// and where each resumes. Backed by the learner's profile in the app; a
/// subclass stands in for it in tests, so the sequence and queue logic is
/// testable without a live user.
class TutorialProgressSource {
  const TutorialProgressSource();

  bool isEnabled(TutorialEnum tutorial) => tutorial.globallyEnabled;

  int resumeStep(TutorialEnum tutorial) => tutorial.stepProgress;
}
