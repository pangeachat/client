import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';

sealed class TutorialStateTransitionEvent {
  const TutorialStateTransitionEvent();
}

/// Sets the execution details [TutorialModel] for the next tutorial to be launched
class LaunchTutorialEvent extends TutorialStateTransitionEvent {
  final TutorialModel tutorial;
  const LaunchTutorialEvent(this.tutorial);
}

/// Updates whether or not a tutorial step is transitioning.
class TutorialTransitionEvent extends TutorialStateTransitionEvent {
  final bool isTransitioning;
  const TutorialTransitionEvent(this.isTransitioning);
}

/// Moves the tutorial state machine forward, either to the next step or the next tutorial if the current step is the last in its sequence.
class ForwardTutorialEvent extends TutorialStateTransitionEvent {
  const ForwardTutorialEvent();
}

/// Moves the tutorial state machine backward, either to the previous step or the previous tutorial if the current step is the first in its sequence.
class BackTutorialEvent extends TutorialStateTransitionEvent {
  const BackTutorialEvent();
}

/// Resets the active tutorial. This is used when a tutorial is exited before completion.
class ResetTutorialEvent extends TutorialStateTransitionEvent {
  const ResetTutorialEvent();
}
