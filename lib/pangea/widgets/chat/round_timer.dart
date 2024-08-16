import 'package:fluffychat/pangea/constants/game_constants.dart';
import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

/// Create a timer that counts down to the given time
/// Default duration is 180 seconds
class RoundTimer extends StatelessWidget {
  final int currentSeconds;
  final int maxSeconds;
  final Color timerColor;

  const RoundTimer(
    this.currentSeconds,
    this.maxSeconds,
    this.timerColor, {
    super.key,
  });

  int get remainingTime => maxSeconds - currentSeconds;

  String get timerText =>
      '${(remainingTime ~/ 60).toString().padLeft(2, '0')}:${(remainingTime % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    double percent = currentSeconds / GameConstants.timerMaxSeconds;
    if (percent > 1) percent = 1;
    return CircularPercentIndicator(
      radius: 40.0,
      percent: percent,
      backgroundColor: timerColor.withOpacity(0.5),
      progressColor: timerColor,
      animation: true,
      animateFromLastPercent: true,
      center: Text(timerText),
      animateToInitialPercent: false,
    );
  }
}
