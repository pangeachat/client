import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';

/// Shared layout metrics and text style for the goal header, used by both its
/// faces (the collapsed header and the expanded content) and both wrappers.
class GoalHeaderConstants {
  /// Width reserved on each side of the top row so the centered content stays
  /// centered while the chevron sits flush right.
  static const double chevronSlot = 24.0;

  /// The width of each side slot when the header carries the session's XP at
  /// its left (#9559): the XP's room, mirrored on the chevron's side so the
  /// diamonds stay centred. A longer total scales down to fit.
  static const double xpSlot = 64.0;

  /// Margin between the card's border and whatever it floats over.
  static double cardMargin(BuildContext context) =>
      FluffyThemes.isColumnMode(context) ? 8.0 : 4.0;

  /// Padding above the star row (collapsed) and above the first goal row
  /// (expanded), kept identical so the top of the header doesn't shift on
  /// expand. The collapsed star row carries it below itself too, so its hover
  /// highlight is a symmetric band instead of stopping flush under the stars.
  ///
  /// A narrow window gets the tighter value: the card floats over the
  /// conversation, and on a phone with the keyboard up the padding it spends
  /// is most of the chat the learner has left (#9147). 8.0 still leaves the
  /// toggle row a 52px tap target around the 36px star box.
  static double topPadding(BuildContext context) =>
      FluffyThemes.isColumnMode(context) ? 14.0 : 8.0;

  /// Max height of the scrolling portion of the goal list (the goals below the
  /// pinned top row). Sized to hold ~3 two-line rows, so a 4-goal list — one
  /// pinned plus three here — never scrolls however long each goal is.
  static const double goalsScrollMaxHeight = 190.0;

  /// The same cap when every goal scrolls — the in-session list, whose top
  /// row is the session's XP rather than the first goal (#9559): one more
  /// two-line row, so a 4-goal list still never scrolls.
  static const double allGoalsScrollMaxHeight = 250.0;

  /// The emphasized 15px label shared by the goal header's title and its
  /// active-goal subtitle, across both faces and both wrappers.
  static const TextStyle labelStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}
