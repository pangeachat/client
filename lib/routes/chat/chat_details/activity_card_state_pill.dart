import 'package:flutter/material.dart';

/// The state pill an `ActivitySuggestionCard` shows in place of its live
/// state's own: a discussion's "Joined" or "Answered" (#9647).
class ActivityCardStatePill {
  final String label;

  /// Null keeps the live state's glyph, or none without one.
  final IconData? icon;

  /// The pill's colours; null keeps the live state's. With them the pill
  /// shows on a card with no live state, and so no frame.
  final Color? fill;
  final Color? onFill;

  const ActivityCardStatePill({
    required this.label,
    this.icon,
    this.fill,
    this.onFill,
  });
}
