import 'package:flutter/material.dart';

/// Shared layout metrics and text style for the goal header, used by both its
/// faces (the collapsed header and the expanded content) and both wrappers.
class GoalHeaderConstants {
  /// Width reserved on each side of the top row so the centered content stays
  /// centered while the chevron sits flush right.
  static const double chevronSlot = 24.0;

  /// Padding above the star row (collapsed) and above the first goal row
  /// (expanded), kept identical so the top of the header doesn't shift on
  /// expand. The collapsed star row carries it below itself too, so its hover
  /// highlight is a symmetric band instead of stopping flush under the stars.
  static const double topPadding = 14.0;

  /// Max height of the scrolling portion of the goal list (the goals below the
  /// pinned top row). Sized to hold ~3 two-line rows, so a 4-goal list — one
  /// pinned plus three here — never scrolls however long each goal is.
  static const double goalsScrollMaxHeight = 190.0;

  /// The emphasized 15px label shared by the goal header's title and its
  /// active-goal subtitle, across both faces and both wrappers.
  static const TextStyle labelStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}
