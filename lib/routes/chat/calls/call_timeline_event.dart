import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/transcript_view.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// The other side of a 1:1 conversation, or null when it cannot be told.
///
/// ONE answer, because several places need it and each one that worked it out
/// for itself got a different answer. The transcript reader had a fallback for
/// a missing m.direct, the direction of a call did not, and the card's own
/// legitimacy check did not either -- so the same unsynced account data showed
/// a real speaker no row at all in one place and the wrong arrow in another.
///
/// m.direct first: it records who the conversation is WITH and survives them
/// leaving the room, which membership does not. Failing that, membership --
/// server-enforced state, not content anyone can write.
///
/// Joined members are tried before ever-members. A pair with a third person
/// who joined and left is still a pair now, and looking only at the wider set
/// made it ambiguous and gave up. Ambiguity yields null rather than a guess:
/// naming the wrong person is worse than naming nobody, in both consumers.
String? callPeerOf(Room room) {
  final direct = room.directChatMatrixID;
  if (direct != null) return direct;

  final me = room.client.userID;
  Set<String> others(List<Membership> filter) => room
      .getParticipants(filter)
      .map((m) => m.id)
      .where((id) => id != me)
      .toSet();

  final joined = others(const [Membership.join]);
  if (joined.length == 1) return joined.single;

  final ever = others(const [Membership.join, Membership.leave]);
  return ever.length == 1 ? ever.single : null;
}

/// The two people a 1:1 call in [room] can have been between.
///
/// Local state only. A Matrix sender id is stamped by the homeserver rather
/// than chosen by the writer, so a card or a half claiming to come from
/// somebody else cannot pass a check against this set.
///
/// PRIVATE, and it stays private. This is the raw set, and reading it directly
/// is how "the peer is unknown" gets mistaken for "the peer is nobody" -- it
/// holds one id in that case, and `contains` then answers false for a real
/// person. Every caller wants the RULE, which is [callCardCouldBeReal].
Set<String> _callSides(Room room) => {?room.client.userID, ?callPeerOf(room)};

/// Whether a newly arrived event may take over the room's chat-list line.
///
/// Only interesting when it and the line's current event are cards for the
/// SAME call, which happens for real: the writer's card is sent at hangup, its
/// delivery to the other device is delayed past the settle window by ordinary
/// network flakiness, and that device writes a survivor card carrying the same
/// call key and its own independently measured duration. Both are genuine.
///
/// The conversation keeps the earlier one. The list had no idea that rule
/// existed and simply took whatever arrived last, so the two surfaces
/// deterministically described one call with two different durations. Not a
/// coincidence -- the survivor card is always the later one, so it always won
/// the line.
///
/// Both cards must be able to vouch for themselves before this arbitrates:
/// letting one that cannot displace one that can would remove a real record
/// from the list, which is the thing the strict predicate exists to stop.
bool callCardMayTakeTheChatListLine(Event? current, Event incoming) {
  // Only call cards are ours to arbitrate. Everything else the room sends
  // reaches the line the way it always did.
  if (incoming.type != PangeaEventTypes.call) return true;

  // A record advancing through its OWN lifecycle is not a rival card, and it
  // must never be refused. A locally sent event is echoed at status sending
  // and, if the send fails, echoed again as the same event id with status
  // error. Comparing those two by rank is a tie -- same timestamp, same id --
  // which refused the update and froze the line on the stale sending copy
  // forever. The chat list then showed a cheerful "Voice call" for a call the
  // peer never received, while the conversation correctly showed nothing.
  //
  // "The same record" also covers the hop from the local echo to the version
  // the server accepted, which arrives under a DIFFERENT id: the echo is keyed
  // by the transaction id, and the accepted event carries that transaction id
  // back. Both echoes share one timestamp, so without this the tie would be
  // settled by comparing a transaction id string against a `$`-prefixed event
  // id -- which resolves correctly today only because this app's transaction
  // ids happen to start with a letter, which sorts after `$`. That is luck,
  // not an invariant, and rank arbitration was built for two independently
  // authored rival cards rather than for one record confirming itself.
  if (current != null && _sameRecord(current, incoming)) return true;

  // Something that cannot produce a line must not be allowed to take it.
  // Otherwise it wins the slot and renders as nothing, and a real call that
  // IS being drawn in the conversation loses its summary entirely -- a blank
  // row rather than a wrong one.
  //
  // This is the direction the previous version could not see. It asked
  // whether EITHER side was unproven, which conflated two different things:
  // unproven because nobody is identifiable, and unproven because this sender
  // is identifiably not a participant. The first is a shrug and the second is
  // a refusal, and treating them alike let a forged card blank the line for a
  // real one.
  if (!callCardCanBeSummarised(incoming)) return false;

  if (current == null) return true;
  if (!CallTimelineEvent.sameCall(incoming, current)) return true;

  // Between two cards for one call, rank decides -- but only when both can
  // vouch for themselves. Where neither can, the conversation draws both and
  // the line shows one of them, which is the declared duplicate-card cost.
  if (!callCardIsProvenReal(incoming) || !callCardIsProvenReal(current)) {
    return true;
  }
  return CallTimelineEvent.outranks(incoming, current);
}

/// Whether these are two sightings of ONE record rather than rival cards.
///
/// The same event id, or the local echo and the accepted event that carries
/// its transaction id back.
bool _sameRecord(Event current, Event incoming) =>
    current.eventId == incoming.eventId ||
    incoming.transactionId == current.eventId ||
    current.transactionId == incoming.eventId;

/// Whether the chat list would have anything to say about this card.
///
/// One answer, asked by the two places that need it: [callPreviewLine], which
/// renders the line, and [callCardMayTakeTheChatListLine], which decides who
/// holds it. They were separate judgements, and the gap between them is how a
/// card that renders as nothing came to win the slot from one that renders.
bool callCardCanBeSummarised(Event event) =>
    !event.status.isError && callCardCouldBeReal(event);

/// Whether this call card could have been written by somebody on the call.
///
/// COULD, not IS, and the difference is the whole of it. Anyone in the room
/// can send an event of this type, so a card from a third party must not draw:
/// it would put a call on screen that never happened, with a duration and a
/// transcript affordance. But [callPeerOf] answers null when it cannot tell
/// who the other side is -- an ordinary thing once that person leaves the room
/// -- and reading that null as "they were not a participant" hid the real card
/// for a call that really happened, on every surface, along with the
/// transcript it opens.
///
/// Null is not a denial. When the peer is unknown nobody is excluded, which
/// costs a forged card being DRAWN in a room we could not resolve, and saves
/// every real call in a room the other person has left. Losing a real call is
/// the worse of the two and much the likelier: the forgery needs a hostile
/// room member, and the peer leaving needs nothing at all.
///
/// This answer is for SHOWING a card and nothing else. Deciding whether one
/// card may displace another, or stand in for one not yet written, is a
/// different question with the opposite risk -- see [callCardIsProvenReal].
bool callCardCouldBeReal(Event event) {
  final peer = callPeerOf(event.room);
  if (peer == null) return true;
  return _callSides(event.room).contains(event.senderId);
}

/// Whether this card is PROVEN to come from somebody on the call.
///
/// The same question as [callCardCouldBeReal] with the unknown resolved the
/// other way, because the consequence runs the other way. Showing a card we
/// cannot vouch for adds something visible and harmless. Letting a card we
/// cannot vouch for suppress another, or count as one already written,
/// REMOVES a real record -- and removal is silent, and takes the transcript's
/// only tap target with it.
///
/// One principle, two answers: an unknown is resolved toward keeping records,
/// never toward removing them.
///
/// The cost is stated plainly: when the peer cannot be identified, two
/// genuine cards for one call both draw, because neither can prove itself
/// entitled to suppress the other. A visible duplicate of a call that really
/// happened is a far better failure than a real call disappearing, which is
/// what the permissive answer allowed -- a third party who was in the room
/// during the call knows the call key, and a card carrying it and an earlier
/// timestamp suppressed the truthful one and told the survivor not to bother
/// writing at all.
bool callCardIsProvenReal(Event event) {
  final peer = callPeerOf(event.room);
  if (peer == null) return false;
  return _callSides(event.room).contains(event.senderId);
}

/// Whether this account placed the call.
///
/// From the stated caller, not from who wrote the event: the writer is chosen
/// deterministically so exactly one card exists, and that is not always the
/// side that called -- a card recovered by the survivor is written by the
/// side that did NOT call. Older events carry no caller, so the sender stands
/// in. One reading, shared by the card and the chat list, so the two cannot
/// tell the learner different things about the same call.
bool callWasOutgoing(Event event) {
  final me = event.room.client.userID;
  final caller = event.content['caller'];

  // Believed only when it names one of the two real sides of this call. It
  // cannot be checked against the sender -- the card is written by the
  // survivor as often as by the caller, which is the whole reason the field
  // exists -- so it is checked against the only two people a 1:1 call can
  // have. That rejects a stranger, and rejects a value that is not a user id
  // at all.
  //
  // What it does NOT do, and cannot: stop the peer claiming that either of
  // the two of us dialled. They are a real party to the call and they wrote
  // the card, and there is no independent record of who pressed the button --
  // if there were, this field would not be needed. So a modified peer client
  // can still show the other person the wrong arrow for a call they were both
  // on. That is the honest limit here: the label can be wrong between two
  // people who were really talking, and no third party can be inserted.
  // When the peer cannot be worked out we cannot confirm the name -- and
  // rejecting it then discarded a TRUTHFUL value written by our own side: a
  // survivor card correctly naming the peer who called, read back as a call we
  // placed. An unconfirmable name is still only ever one of the two people in
  // a 1:1 room, so believing it costs at most the arrow, which the peer could
  // flip anyway.
  final peer = callPeerOf(event.room);
  if (caller is String && (caller == me || peer == null || caller == peer)) {
    return caller == me;
  }

  // Anything else, including a non-string: fall back to the writer, which is
  // where this stood before the field existed.
  return event.senderId == me;
}

/// What the CHAT LIST says about a room whose newest event is a call.
///
/// The same words the card in the conversation uses, so the list and the
/// conversation agree. Hiding the membership plumbing stopped the list
/// reading "sent a com.famedly.call.member event", but on its own it left
/// "No messages yet" on a room where two people had just talked -- and the
/// SDK's own fallback for an unknown message type is no better ("User sent a
/// pangea.call event"). A call is worth a line of its own.
/// Null when there is nothing to say about this call.
///
/// A send that failed is kept in the LOCAL timeline and marked errored;
/// nothing retries it and the peer never receives it. The card in the
/// conversation already refuses to draw one, because a record only one side
/// holds reads as a call that never happened. The list had no such check, so
/// the same event vanished from the conversation and stayed in the chat list
/// as a plausible "Voice call - 2:14" the other person had never seen. The two
/// surfaces are supposed to agree; that is the whole reason this function
/// exists.
String? callPreviewLine(L10n l10n, Event event) {
  if (!callCardCanBeSummarised(event)) return null;
  final outgoing = callWasOutgoing(event);
  final declined = event.content['declined'] == true;
  final answered = event.content['answered'] == true;
  final video = event.content['video'] == true;
  if (declined) {
    return outgoing ? l10n.callHistoryDeclined : l10n.callHistoryYouDeclined;
  }
  if (!answered) {
    if (outgoing) return l10n.callHistoryNoAnswer;
    return video ? l10n.callHistoryMissedVideoCall : l10n.callHistoryMissedCall;
  }
  final label = video ? l10n.callHistoryVideoCall : l10n.callHistoryVoiceCall;
  final duration = CallRecord.durationOf(event.content);
  if (duration == null) return label;
  return '$label · ${CallTimelineEvent.formatDuration(duration)}';
}

/// One finished call, drawn in the timeline.
///
/// Centred, like a join or an invitation, because a call is something that
/// HAPPENED in the conversation rather than something one side said. Drawing it
/// as a chat bubble would attribute it to whoever's client wrote it and align it
/// to their edge, which reads as a message from them.
///
/// The same event is read from both sides of a direct message, so direction is
/// derived per viewer: the account that placed the call sees it as outgoing, the
/// other as incoming.
class CallTimelineEvent extends StatelessWidget {
  final Event event;

  /// The surrounding timeline, for the first-per-key rule below. Required so
  /// no call site can forget it exists; nullable because a card can render
  /// where no timeline is at hand (a preview, a test) -- there the rule
  /// simply cannot run and the card draws.
  final Timeline? timeline;

  const CallTimelineEvent(this.event, {required this.timeline, super.key});

  bool get _outgoing => callWasOutgoing(event);

  bool get _video => event.content['video'] == true;

  /// Whether a conversation actually happened. False is a missed call.
  bool get _answered => event.content['answered'] == true;

  /// Turned down, as opposed to simply not picked up. Both are unanswered; only
  /// this one was a deliberate no.
  bool get _declined => event.content['declined'] == true;

  /// Read through the record's own rule, so the card and the thing that wrote
  /// it cannot disagree about what a duration is.
  /// Null when the card states no usable duration. Distinct from a call that
  /// really lasted no time: the card drew "0:00" for both, stating a length
  /// the data did not support, while the chat list showed no length at all for
  /// one of them -- two surfaces contradicting each other about one call.
  Duration? get _duration => CallRecord.durationOf(event.content);

  /// Whether another card for the SAME call precedes this one.
  ///
  /// Matrix transaction ids dedup PER DEVICE, so two devices writing the same
  /// call -- the writer and the survivor racing across the settle window --
  /// cannot be collapsed by the server. The idempotency lives HERE instead,
  /// per the idempotent-receiver rule: every writer stamps the call's shared
  /// key, and only the FIRST card per key in timeline order is drawn. Order is
  /// origin_server_ts with the event id as the final tie-break, so every
  /// client picks the same one. Keyless cards -- older clients, calls whose
  /// identity was never learned -- always draw, exactly as before.
  bool get _duplicateOfEarlier {
    final t = timeline;
    return t != null && isDuplicateOfEarlier(event, t.events);
  }

  /// Which of two cards for the SAME call the surfaces agree to keep.
  ///
  /// Earliest by origin_server_ts, with the event id as the final tie-break so
  /// every client picks the same one. Exported because the chat list has to
  /// reach the same verdict as the conversation from a different direction:
  /// the conversation sees the whole timeline, the list sees only the incoming
  /// event and the one it already held.
  static bool outranks(Event a, Event b) {
    final byTime = a.originServerTs.compareTo(b.originServerTs);
    if (byTime != 0) return byTime < 0;
    return a.eventId.compareTo(b.eventId) < 0;
  }

  /// Whether two events are cards for the same call.
  static bool sameCall(Event a, Event b) {
    final key = a.content[CallRecord.callKeyField];
    return key is String &&
        a.type == PangeaEventTypes.call &&
        b.type == PangeaEventTypes.call &&
        b.content[CallRecord.callKeyField] == key;
  }

  /// The rule itself, pure so it can be pinned directly: [event] is a
  /// duplicate iff some other sent call card in [all] carries the same key
  /// and sorts earlier -- origin_server_ts first, event id as the final
  /// tie-break, so every client picks the same survivor of a double-write.
  @visibleForTesting
  static bool isDuplicateOfEarlier(Event event, Iterable<Event> all) {
    if (event.content[CallRecord.callKeyField] is! String) return false;

    // Only a card written by one of the two people who were on the call can
    // suppress another. The key is the caller's membership event id, which
    // both sides know DURING the call, long before either writes its card --
    // so without this, anyone else in the room could write a card carrying the
    // right key the moment the call starts, win the earliest-timestamp
    // tie-break below, and permanently hide the truthful card behind their
    // own. Setting `declined` on the forgery also removed the tap target that
    // opens the transcript, so the real halves became unreachable while still
    // existing. Sender ids are stamped by the homeserver, not by the writer,
    // which is what makes this check worth anything.
    for (final other in all) {
      if (identical(other, event) || other.eventId == event.eventId) continue;
      // Through the shared match, not a second copy of it. Two independent
      // implementations of "are these the same call" drift the moment one is
      // edited.
      if (!sameCall(event, other)) continue;
      if (other.status.isError) continue;
      // PROVEN, not merely possible. Suppression removes a record, so a card
      // that cannot vouch for itself does not get to do it: otherwise a third
      // party who was in the room during the call -- and therefore knows the
      // call key, which is ordinary room state -- could post a card with an
      // earlier timestamp and make the truthful one disappear.
      //
      // When the peer cannot be identified this means two genuine cards for
      // one call both draw. That is the trade, and it is the right way round:
      // a visible duplicate of a real call beats a real call vanishing.
      if (!callCardIsProvenReal(other)) continue;
      if (outranks(other, event)) return true;
    }
    return false;
  }

  /// Whether this card ever reached the homeserver.
  ///
  /// A send that failed is not dropped by the SDK: it keeps the optimistic echo
  /// in the LOCAL timeline and marks it errored. Nothing ever retries it, and
  /// the peer never receives it, so drawing it puts a call in one person's
  /// history that is absent from the other's -- which is what a call card must
  /// never do. It states a SHARED fact, and a copy only one side has is a claim
  /// the other cannot see.
  bool get _neverSent => event.status.isError;

  /// The anchor both devices related their transcript halves to.
  ///
  /// Also the card's dedup key, and the same value for both: there is one
  /// identity per call, and a transcript that hung off a different one could
  /// not be found from the card that represents it.
  String? get _callKey {
    final key = event.content[CallRecord.callKeyField];
    return key is String && key.isNotEmpty ? key : null;
  }

  /// Whether this card can lead anywhere.
  ///
  /// A call that never connected has nothing to transcribe, and a call whose
  /// key was never learned has nothing to query -- both are unopenable, and
  /// offering the tap anyway would promise a page that can only apologise.
  ///
  /// A call that DID connect may still turn out to have no halves. That is not
  /// knowable without a read, so the tap is offered and the screen answers
  /// honestly rather than the card guessing.
  bool get _openable => _answered && !_declined && _callKey != null;

  @override
  Widget build(BuildContext context) {
    // Nothing, rather than a phantom. The call itself still happened; what
    // failed is the record of it, and a record only one side holds is worse
    // than no record -- it reads as an extra call that never took place.
    if (_neverSent) return const SizedBox.shrink();
    // A card from somebody who was not on the call is not a record of it.
    if (!callCardCouldBeReal(event)) return const SizedBox.shrink();
    if (_duplicateOfEarlier) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final missed = !_answered && !_declined;
    final connected = _answered && !_declined;

    // A call that connected is unremarkable; one that was missed or turned down
    // is the thing a learner scrolls back to find. Colour follows that, not the
    // call's direction.
    final color = connected ? const Color(0xFF2E7D32) : theme.colorScheme.error;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Center(
        child: Material(
          color: theme.colorScheme.surface.withAlpha(128),
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 3),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 3),
            // Null when there is nothing to open, which also removes the
            // ripple: an affordance that leads nowhere is worse than none.
            onTap: _openable ? () => _openTranscript(context) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_icon(missed), size: 16, color: color),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      _label(l10n, missed),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (connected && _duration != null) ...[
                    Text(
                      '  ${formatDuration(_duration!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (_openable) ...[
                    const SizedBox(width: 7),
                    Tooltip(
                      message: l10n.callTranscriptOpen,
                      child: Icon(
                        Icons.notes,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Guarded by [_openable], so the key is known to be there. Read again
  /// rather than captured, because the build that drew the card and the tap
  /// that follows it are separate moments.
  void _openTranscript(BuildContext context) {
    final key = _callKey;
    if (key == null) return;
    showCallTranscript(context, room: event.room, callKey: key);
  }

  IconData _icon(bool missed) {
    if (_declined) return Icons.phone_disabled_outlined;
    if (missed) {
      return _outgoing ? Icons.call_missed_outgoing : Icons.call_missed;
    }
    if (_video) return Icons.videocam;
    return _outgoing ? Icons.call_made : Icons.call_received;
  }

  String _label(L10n l10n, bool missed) {
    if (_declined) {
      return _outgoing ? l10n.callHistoryDeclined : l10n.callHistoryYouDeclined;
    }
    if (missed) {
      if (_outgoing) return l10n.callHistoryNoAnswer;
      return _video
          ? l10n.callHistoryMissedVideoCall
          : l10n.callHistoryMissedCall;
    }
    return _video ? l10n.callHistoryVideoCall : l10n.callHistoryVoiceCall;
  }

  /// `M:SS`, or `H:MM:SS` once a call runs past an hour. Seconds are always two
  /// digits so the colon does not jump around as a call ticks over.
  static String formatDuration(Duration d) {
    final seconds = d.inSeconds;
    final s = (seconds % 60).toString().padLeft(2, '0');
    final m = (seconds ~/ 60) % 60;
    final h = seconds ~/ 3600;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
    return '$m:$s';
  }
}
