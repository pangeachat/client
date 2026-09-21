import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/bot_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Whether [room] should be OFFERED call buttons.
///
/// A bot DM is a direct chat, so `isDirectChat` alone is not enough. The bot
/// has no VoIP: calling it rings nobody and the caller sits through the
/// no-answer timeout for a call that was never going to connect. The room's
/// other controls already hide themselves this way (see
/// `pangea_chat_input_row`).
///
/// Deliberately NOT the same question as `CallService.couldRingHere`, which
/// asks whether a ring ALREADY IN this room could be a 1:1 call for us.
///
/// Both reads here come from data that arrives with a sync, so both are wrong
/// while it is missing -- in opposite directions, and neither is corrected
/// here:
///
/// - `isDirectChat` resolves `m.direct` account data, so before that has
///   loaded a genuine two-person HUMAN DM also reads false and is offered no
///   buttons. `couldRingHere` carries a `mJoinedMemberCount == 2` fallback for
///   exactly that case, and it is deliberately not copied to this side. There
///   it recovers a real incoming call, which the live ring stream never
///   redelivers, so guessing "no" loses the call outright. Here the same
///   fallback would start OFFERING calls in any two-person GROUP room, and v1
///   is direct messages only -- that is a product change, not a bug fix. What
///   leaving it out costs is the buttons staying hidden, with nothing here
///   that brings them back: the header rebuilds off `client.onRoomState` for
///   this room (`chat_view.dart`), and `m.direct` arrives on `onAccountData`,
///   which nothing on this path listens to. So they appear on whatever
///   unrelated rebuild happens next, and there is no telling when that is.
///   Still late buttons rather than a dropped call, but late by an unbounded
///   amount.
/// - `isBotDM` falls back to the room's `bot_options` state for a bot room
///   that `m.direct` files under some other user id. Until that state has
///   synced such a room reads as an ordinary DM and IS offered the buttons.
///   There is no fix at this layer: a bot room cannot be recognised from state
///   the client does not have yet, and the one lookup available -- who is in
///   the room -- does not answer the question either, since the bot is a
///   member of ordinary rooms as well. The window closes on the sync that
///   delivers the state, and what it costs meanwhile is a button that rings a
///   bot which never answers, the same no-op this gate exists to remove.
///   Nothing is dropped or misrouted.
bool _offersCalls(Room room) => room.isDirectChat && !room.isBotDM;

/// Starts a call from the room's own header.
///
/// A call already running somewhere else refuses rather than swallowing this
/// one, so that ANSWERING a ring for another room can decline it as busy.
/// Pressing Call is the other intent: there is nothing to tell the other side,
/// and the useful thing is simply to show the call already in progress --
/// which the refusal has already brought forward.
void _startCall(BuildContext context, Room room, {required bool video}) {
  try {
    Matrix.of(context).startCall(room, video: video);
  } on AlreadyInACall {
    Logs().i('Already on a call; showing that one instead');
  }
}

/// The chat header's Call and Video call buttons, and the decision of whether
/// to offer them at all.
///
/// The decision lives in here rather than in the app bar that mounts this,
/// because `ChatView._appBarActions` cannot be mounted without a live
/// `ChatController` and so cannot be tested. A gate written there is a gate
/// only the helper is pinned for: the site can quietly stop asking it and
/// every test still passes. Holding it inside a widget that stands up on its
/// own makes the test that pins the gate the same test that pins what renders.
class ChatCallButtons extends StatelessWidget {
  final Room room;

  const ChatCallButtons(this.room, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!_offersCalls(room)) return const SizedBox.shrink();

    // Only where the homeserver advertises an RTC focus -- offering a button
    // that cannot work is worse than not offering one. Group calls are the same
    // transport with more members and land later. The focus is discovered over
    // the network, so the buttons appear once the answer is in rather than
    // flickering on a guess. The future is memoized on the service, so this is
    // one request per account, not one per room opened.
    return FutureBuilder(
      future: Matrix.of(context).callService.resolveFocus(),
      builder: (context, snapshot) => snapshot.data == null
          ? const SizedBox.shrink()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Labelled explicitly. An IconButton's tooltip is not reaching
                // the accessibility tree in this build, so these reach a screen
                // reader as two unnamed buttons -- and an end-to-end test cannot
                // find them by anything but their pixel position, which is how
                // the call harness came to be clicking empty space after a
                // layout change.
                Semantics(
                  button: true,
                  label: L10n.of(context).startVideoCall,
                  child: IconButton(
                    icon: const Icon(Icons.videocam_outlined),
                    tooltip: L10n.of(context).startVideoCall,
                    onPressed: () => _startCall(context, room, video: true),
                  ),
                ),
                Semantics(
                  button: true,
                  label: L10n.of(context).startCall,
                  child: IconButton(
                    icon: const Icon(Icons.call_outlined),
                    tooltip: L10n.of(context).startCall,
                    onPressed: () => _startCall(context, room, video: false),
                  ),
                ),
              ],
            ),
    );
  }
}
