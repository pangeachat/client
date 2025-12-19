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
  late int _elapsedSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _elapsedSeconds = widget.initialSeconds;
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsedSeconds++;
      });
      widget.onTimeUpdate(_elapsedSeconds);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatTime(_elapsedSeconds),
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}
