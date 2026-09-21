import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// What a room-scoped panel (a chat, its details, invite, emotes or search
/// page, the course card) renders when the room it names cannot be resolved —
/// an unknown or hand-edited id, or a room the user has left.
///
/// The page renders its own chrome, so per routing.instructions.md ("Closing a
/// panel: X or back arrow") it must place the panel's close control in that
/// chrome. [closeButton] is required so a new call site cannot strand the
/// learner on a panel with no way out (#7746, #8322, #8327).
class RoomUnavailablePanel extends StatelessWidget {
  final Widget closeButton;

  const RoomUnavailablePanel({super.key, required this.closeButton});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: closeButton,
        title: Text(L10n.of(context).oopsSomethingWentWrong),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            L10n.of(context).youAreNoLongerParticipatingInThisChat,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
