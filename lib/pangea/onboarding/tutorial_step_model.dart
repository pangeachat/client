import 'package:fluffychat/pangea/onboarding/tutorial_events_event.dart';

class TutorialStep {
  final String anchorId;
  final String message;
  final TutorialEvent? completeWhen;
  final double borderRadius;
  final double padding;

  const TutorialStep({
    required this.anchorId,
    required this.message,
    this.completeWhen,
    this.borderRadius = 16.0,
    this.padding = 8.0,
  });

  Map<String, dynamic> toJson() => {
    'anchorId': anchorId,
    'message': message,
    'completeWhen': completeWhen?.name,
    'borderRadius': borderRadius,
    'padding': padding,
  };
}
