import 'package:fluffychat/pangea/onboarding/tutorial_model.dart';

sealed class TutorialStateTransitionEvent {
  const TutorialStateTransitionEvent();
}

class EnqueueSequenceEvent extends TutorialStateTransitionEvent {
  final TutorialSequence sequence;
  const EnqueueSequenceEvent(this.sequence);
}

class LaunchTutorialEvent extends TutorialStateTransitionEvent {
  final TutorialModel tutorial;
  const LaunchTutorialEvent(this.tutorial);
}

class PreviousTutorialEvent extends TutorialStateTransitionEvent {
  const PreviousTutorialEvent();
}

class BeginStepTransitionEvent extends TutorialStateTransitionEvent {
  const BeginStepTransitionEvent();
}

class EndStepTransitionEvent extends TutorialStateTransitionEvent {
  const EndStepTransitionEvent();
}

class CloseTutorialEvent extends TutorialStateTransitionEvent {
  const CloseTutorialEvent();
}

class ResetSequenceEvent extends TutorialStateTransitionEvent {
  const ResetSequenceEvent();
}
