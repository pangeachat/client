import 'package:flutter/widgets.dart';

class AudioPlaybackSpeedController {
  ValueNotifier<double> playbackSpeed = ValueNotifier<double>(1.0);

  AudioPlaybackSpeedController();

  void dispose() {
    playbackSpeed.dispose();
  }

  void toggleSpeed() {
    switch (playbackSpeed.value) {
      case 1.0:
        playbackSpeed.value = 0.75;
        break;
      case 0.75:
        playbackSpeed.value = 0.5;
        break;
      case 0.5:
        playbackSpeed.value = 1.25;
        break;
      case 1.25:
        playbackSpeed.value = 1.5;
        break;
      default:
        playbackSpeed.value = 1.0;
    }
  }

  void setSpeed(double speed) {
    playbackSpeed.value = speed;
  }
}
