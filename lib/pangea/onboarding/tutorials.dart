import 'package:fluffychat/pangea/onboarding/tutorial_events_event.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_step_model.dart';

class Tutorials {
  static final selectMessageTutorial = [
    const TutorialStep(
      anchorId: "message_bubble",
      message: "Tap the message to select it.",
      completeWhen: TutorialEvent.messageSelected,
      borderRadius: 18.0,
    ),
  ];

  static final messageToolbarTutorial = [
    const TutorialStep(
      anchorId: "translate_button",
      message: "Tap here to translate the message.",
      completeWhen: TutorialEvent.translateUsed,
      borderRadius: 100.0,
    ),
    const TutorialStep(
      anchorId: "tts_button",
      message: "Tap here to listen to the message.",
      completeWhen: TutorialEvent.ttsUsed,
      borderRadius: 100.0,
    ),
  ];
}
