import 'dart:async';

import 'package:flutter/material.dart';

class VocabTimerWidget extends StatefulWidget {
  final int initialSeconds;
  final ValueChanged<int> onTimeUpdate;
  final bool isRunning;

  const VocabTimerWidget({
    required this.initialSeconds,
    required this.onTimeUpdate,
    this.isRunning = true,
    super.key,
  });

  @override
  VocabTimerWidgetState createState() => VocabTimerWidgetState();
}

class VocabTimerWidgetState extends State<VocabTimerWidget> {
  final Stopwatch _stopwatch = Stopwatch();
  late int _initialSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initialSeconds = widget.initialSeconds;
    if (widget.isRunning) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(VocabTimerWidget oldWidget) {
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
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final currentSeconds = _getCurrentSeconds();
      setState(() {});
      widget.onTimeUpdate(currentSeconds);
    });
  }

  void _stopTimer() {
    _stopwatch.stop();
    _timer?.cancel();
    _timer = null;
  }

  int _getCurrentSeconds() {
    if (!_stopwatch.isRunning) {
      return widget.initialSeconds;
    }
    return _initialSeconds + (_stopwatch.elapsedMilliseconds / 1000).round();
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.alarm, size: 20),
        const SizedBox(width: 4.0),
        Text(
          _formatTime(_getCurrentSeconds()),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
