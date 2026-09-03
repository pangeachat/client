import 'dart:async';

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

/// How many people the server counts as JOINED to [room] right now.
///
/// Read from the room SUMMARY (`m.joined_member_count`) -- the server's own
/// authoritative tally -- and deliberately NOT from
/// `room.getParticipants([Membership.join]).length`. Both claim to answer "how
/// many are in this room", and here they are not interchangeable:
///
/// - `getParticipants` counts only the `m.room.member` states the client has
///   LOADED. Under lazy loading -- Matrix's default -- "this list may not be
///   complete" (the SDK's own words on the method). An established two-person
///   DM restored from a sync that did not ship the peer's member event then
///   counts as one joined, and would grey a callable DM until some later state
///   load happened to arrive. The SDK itself does not trust this count on its
///   own: `Room.participantListComplete` compares it AGAINST the summary count
///   to decide whether the loaded list can even be believed.
/// - The summary count does not depend on which member events are in memory.
///   The SDK merges each sync's summary over the last rather than replacing it
///   (`client.dart`: `summary.toJson()..addAll(update)`), so once the server
///   has reported a count it PERSISTS across later syncs that do not restate
///   it -- it does not fall back to `null` on an unrelated sync. `null` here
///   means only that no count has ever been synced -- a brand-new room -- and
///   `(null ?? 0)` greys the buttons until the first sync carries one, which
///   is the safe direction: do not offer a call that cannot be shown to
///   connect.
///
/// `_offersCalls` keeps this to direct chats, so "two joined" is the two people
/// of the DM, never a third party in a group.
int _joinedCount(Room room) => room.summary.mJoinedMemberCount ?? 0;

/// Whether a call placed from [room] right now could connect: this account is
/// JOINED, and the server counts someone else joined too.
///
/// The joined count includes this account, so it cannot on its own tell "two
/// people are here" from "I have LEFT a room that still remembers two". A leave
/// arrives under `rooms.leave`, which carries no summary: the SDK sets the
/// room's membership to `leave` (`client.dart`, `_storeArchivedRoom`) but does
/// not lower the now-stale joined count. So membership is the half that moves
/// when the account itself leaves, and reading both is what makes the buttons
/// go inert then -- not only when the peer leaves and the count does drop.
bool _canCallFrom(Room room) =>
    room.membership == Membership.join && _joinedCount(room) >= 2;

/// The chat header's Call and Video call buttons, and the decision of whether
/// to offer them at all.
///
/// The decision lives in here rather than in the app bar that mounts this,
/// because `ChatView._appBarActions` cannot be mounted without a live
/// `ChatController` and so cannot be tested. A gate written there is a gate
/// only the helper is pinned for: the site can quietly stop asking it and
/// every test still passes. Holding it inside a widget that stands up on its
/// own makes the test that pins the gate the same test that pins what renders.
///
/// A `StatefulWidget` that LISTENS, because what it shows is not fixed for the
/// life of the widget -- whether calls are offered ([_offersCalls]) and whether
/// one could connect ([_canCallFrom]) both turn on room state that moves under
/// the open chat as an invitee accepts, a member leaves, or a room is
/// reclassified. The header that mounts this does rebuild off
/// `client.onRoomState`, but that is not the only signal those answers move on,
/// and this widget is also pumped on its own -- with no header around it --
/// both in tests and as the unit the gate is pinned on. So it subscribes itself
/// to `client.onSync` and rebuilds on it. `onSync` is chosen because it fires
/// once a sync is fully processed: the room summary the count is read from (see
/// [_joinedCount]) is settled by then, whereas `onRoomState` tracks the
/// per-member states the summary count is deliberately trusted over.
class ChatCallButtons extends StatefulWidget {
  final Room room;

  const ChatCallButtons(this.room, {super.key});

  @override
  State<ChatCallButtons> createState() => _ChatCallButtonsState();
}

class _ChatCallButtonsState extends State<ChatCallButtons> {
  /// The subscription this widget rebuilds on. Everything it shows is derived
  /// fresh in `build` from the current room -- whether to offer the buttons at
  /// all ([_offersCalls]) and whether a call could connect ([_canCallFrom]) --
  /// and BOTH turn on room state that only a sync moves. So the widget caches
  /// none of it and simply rebuilds when a sync lands: caching one answer and
  /// guarding the rebuild on it goes stale on the other (a room reclassified as
  /// a bot DM, say, while the joined count holds). The rebuild is two icon
  /// buttons over a memoized focus lookup, cheaper than the staleness a cache
  /// invites.
  StreamSubscription<SyncUpdate>? _sync;

  @override
  void initState() {
    super.initState();
    _listenForSync();
  }

  @override
  void didUpdateWidget(covariant ChatCallButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `build` reads `widget.room`, so a Room object swapped in under the SAME
    // client -- a rejoin, a store reload, a fresh instance for the same id -- is
    // already reflected on the rebuild this triggers. Only a different client is
    // a different `onSync` stream, and that is what the subscription must follow.
    if (oldWidget.room.client != widget.room.client) {
      _listenForSync();
    }
  }

  void _listenForSync() {
    _sync?.cancel();
    _sync = widget.room.client.onSync.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sync?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    if (!_offersCalls(room)) return const SizedBox.shrink();

    // Only where the homeserver advertises an RTC focus -- offering a button
    // that cannot work is worse than not offering one. Group calls are the same
    // transport with more members and land later. The focus is discovered over
    // the network, so the buttons appear once the answer is in rather than
    // flickering on a guess. The future is memoized on the service, so this is
    // one request per account, not one per room opened.
    return FutureBuilder(
      future: Matrix.of(context).callService.resolveFocus(),
      builder: (context, snapshot) {
        if (snapshot.data == null) return const SizedBox.shrink();

        // Offered, but inert until someone else has JOINED. A DM whose invitee
        // has not accepted the invite has only us in it, so a call rings
        // nobody: the recipient hears nothing and the caller sits through the
        // no-answer timeout with no idea why (#8777). Greyed rather than
        // hidden, so the control is visibly there and its being disabled is the
        // signal that a call cannot connect yet.
        //
        // It flips LIVE. The State above rebuilds on `client.onSync`, and
        // `_canCallFrom` reads the room's membership and the server's own joined
        // count from the summary -- so an invitee accepting, a member leaving,
        // or this account leaving re-runs this as soon as the sync carrying it
        // settles. A group room never reaches here -- `_offersCalls` is
        // direct-chats-only -- so "two joined" is the two people of the DM.
        final canCall = _canCallFrom(room);

        return Row(
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
              enabled: canCall,
              label: L10n.of(context).startVideoCall,
              child: IconButton(
                icon: const Icon(Icons.videocam_outlined),
                tooltip: L10n.of(context).startVideoCall,
                onPressed: canCall
                    ? () => _startCall(context, room, video: true)
                    : null,
              ),
            ),
            Semantics(
              button: true,
              enabled: canCall,
              label: L10n.of(context).startCall,
              child: IconButton(
                icon: const Icon(Icons.call_outlined),
                tooltip: L10n.of(context).startCall,
                onPressed: canCall
                    ? () => _startCall(context, room, video: false)
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }
}
