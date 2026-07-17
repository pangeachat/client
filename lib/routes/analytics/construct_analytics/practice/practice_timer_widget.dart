import 'dart:async';

import 'package:flutter/material.dart';

/// Practice session timer — WALL-CLOCK from [startedAt], not time-on-screen.
/// The session keeps counting while its panel is closed (the cluster badge
/// shows the same clock), so the speed bonus rewards finishing in one sitting.
/// See practice-exercises.instructions.md § Session Persistence & Lifecycle.
class PracticeTimerWidget extends StatefulWidget {
  /// Wall-clock zero. Null while the session is still loading.
  final DateTime? startedAt;

  /// Shown when [isRunning] is false (e.g. the elapsed time the session
  /// completed at).
  final int frozenSeconds;

  final ValueChanged<int> onTimeUpdate;
  final bool isRunning;

  const PracticeTimerWidget({
    required this.startedAt,
    required this.onTimeUpdate,
    this.frozenSeconds = 0,
    this.isRunning = true,
    super.key,
  });

  static String formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  PracticeTimerWidgetState createState() => PracticeTimerWidgetState();
}

class PracticeTimerWidgetState extends State<PracticeTimerWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.isRunning) _startTimer();
  }

  @override
  void didUpdateWidget(PracticeTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRunning && !widget.isRunning) {
      _stopTimer();
    } else if (!oldWidget.isRunning && widget.isRunning) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
      widget.onTimeUpdate(_getCurrentSeconds());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  int _getCurrentSeconds() {
    final startedAt = widget.startedAt;
    if (!widget.isRunning || startedAt == null) {
      return widget.frozenSeconds;
    }
    return DateTime.now().difference(startedAt).inSeconds;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.alarm, size: 20),
        const SizedBox(width: 4.0),
        Text(
          PracticeTimerWidget.formatTime(_getCurrentSeconds()),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
