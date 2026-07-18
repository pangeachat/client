import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_timer_widget.dart';

/// The live-practice rendering of a cluster tracker: the practice icon above
/// the session's running wall-clock timer, sized to the tracker's own
/// icon/count metrics so it fully takes the button's place while a session is
/// live. The tracker supplies the stadium background (its hover shape); this
/// widget is just the ticking content. See routing.instructions.md § Practice
/// is a persistent background session.
class PracticeSessionBadge extends StatefulWidget {
  final DateTime startedAt;

  /// Match the host tracker's icon/count sizing so the swap doesn't change
  /// the button's footprint.
  final double iconSize;
  final double fontSize;

  const PracticeSessionBadge({
    required this.startedAt,
    this.iconSize = 24,
    this.fontSize = 16,
    super.key,
  });

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
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    // Content only — the host tracker paints the single stadium fill over its
    // own hover geometry, so the badge never introduces a second shape.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Symbols.fitness_center,
          size: widget.iconSize * 0.85,
          color: onPrimary,
        ),
        const SizedBox(height: 2),
        Text(
          PracticeTimerWidget.formatTime(elapsed),
          style: TextStyle(
            fontSize: widget.fontSize * 0.65,
            height: 1.1,
            fontWeight: FontWeight.w600,
            color: onPrimary,
          ),
        ),
      ],
    );
  }
}
