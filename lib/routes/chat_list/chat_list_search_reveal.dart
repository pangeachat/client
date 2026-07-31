import 'package:flutter/widgets.dart';

import 'package:fluffychat/config/themes.dart';

/// The chat list's search field row mounts as the *first* sliver of the list,
/// so opening search while the user is scrolled down inserts it above the
/// viewport: the field they just asked for is off-screen and all they see is
/// the list shift under them (#7941). Ride the list back to the top so the
/// field lands in view.
///
/// Animated rather than a jump — the motion is what tells the user the list
/// moved on purpose, which is the half of the bug that a silent scroll would
/// leave in place.
///
/// No-op when the list is already at the top (or not laid out yet), so opening
/// search from the top never animates.
void revealChatListSearchField(ScrollController scrollController) {
  if (!scrollController.hasClients || scrollController.position.pixels <= 0) {
    return;
  }
  scrollController.animateTo(
    0,
    duration: FluffyThemes.animationDuration,
    curve: FluffyThemes.animationCurve,
  );
}
