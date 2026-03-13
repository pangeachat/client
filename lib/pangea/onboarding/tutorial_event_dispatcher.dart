import 'dart:async';

import 'package:fluffychat/pangea/onboarding/tutorial_events_event.dart';

class AppEvents {
  static final _controller = StreamController<TutorialEvent>.broadcast();

  static Stream<TutorialEvent> get stream => _controller.stream;

  static void emit(TutorialEvent event) {
    _controller.add(event);
  }
}
