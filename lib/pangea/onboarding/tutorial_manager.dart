import 'package:fluffychat/pangea/onboarding/tutorial_event_dispatcher.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_events_event.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_overlay.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_step_model.dart';
import 'package:flutter/material.dart';

class TutorialManager {
  TutorialManager._();

  static final instance = TutorialManager._();

  OverlayEntry? _overlay;

  List<TutorialStep>? _steps;
  int _index = 0;

  TutorialStep? get current =>
      _steps != null && _index < _steps!.length ? _steps![_index] : null;

  void initialize() {
    AppEvents.stream.listen(_onEvent);
  }

  void _onEvent(TutorialEvent event) {
    debugPrint("TutorialManager received event: $event");
    final step = current;
    debugPrint("Current tutorial step: ${step?.toJson()}");

    if (step == null) return;

    if (step.completeWhen == event) {
      next();
    }
  }

  void start(BuildContext context, List<TutorialStep> steps) {
    if (_overlay != null || steps.isEmpty) return;

    _steps = steps;
    _index = 0;

    _overlay = OverlayEntry(builder: (_) => TutorialOverlay(manager: this));

    Overlay.of(context, rootOverlay: true).insert(_overlay!);
  }

  void next() {
    _index++;
    if (current == null) {
      stop();
    } else {
      // tell the overlay to rebuild
      _overlay?.markNeedsBuild();
    }
  }

  void stop() {
    _overlay?.remove();
    _overlay = null;
    _steps = null;
  }
}
