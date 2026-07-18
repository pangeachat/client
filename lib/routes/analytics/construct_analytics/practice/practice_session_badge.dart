import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_timer_widget.dart';

/// The live-practice label stacked on a section's cluster tracker: the
/// practice icon + the session's running wall-clock timer. Signals the
/// background session and marks the tracker as its resume tap-target. See
/// routing.instructions.md § Practice is a persistent background session.
class PracticeSessionBadge extends StatefulWidget {
  final DateTime startedAt;

  const PracticeSessionBadge({required this.startedAt, super.key});

  @override
  State<PracticeSessionBadge> createState() => _PracticeSessionBadgeState();
}

class _PracticeSessionBadgeState extends State<PracticeSessionBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt).inSeconds;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.fitness_center,
            size: 10.0,
            color: colorScheme.onPrimary,
          ),
          const SizedBox(width: 2.0),
          Text(
            PracticeTimerWidget.formatTime(elapsed),
            style: TextStyle(
              fontSize: 9.0,
              height: 1.0,
              fontWeight: FontWeight.w600,
              color: colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
