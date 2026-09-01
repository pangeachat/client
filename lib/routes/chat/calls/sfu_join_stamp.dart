// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_client/src/internal/events.dart';
import 'package:livekit_client/src/proto/livekit_models.pb.dart' as pb;
import 'package:livekit_client/src/proto/livekit_rtc.pb.dart';

/// The shape of [watchSfuJoinStamp], so a caller can accept it as a seam.
typedef JoinStampWatch =
    CancelListenFunc Function(
      Room room,
      void Function(({int secondsMs, int ms}) stamps) onStamp,
    );

/// The SFU's stamp for this device's join, in MILLISECONDS, read off the join
/// response as it arrives.
///
/// This is the one place in the call code that reaches past livekit_client's
/// public API, and it exists because the public API rounds the reading it
/// exposes. `Participant.joinedAt` reads proto field 6, `joined_at` — whole
/// SECONDS — and multiplies by a thousand. Field 17, `joined_at_ms`, carries
/// the same instant to the millisecond, and on the pinned livekit_client 2.11.0
/// nothing public hands it over: the `ParticipantInfo` that holds it is a
/// private member of `Participant`, and the join response it rides in is
/// consumed inside `Room.connect` without being stored. The signal events are
/// the only place it is reachable at all.
///
/// So this file deep-imports `src/internal/events.dart` for the signal events
/// and `src/proto/` for the messages they carry, and reads `Room.engine`, which
/// is `@internal`. Both are suppressed at the top of THIS file and nowhere
/// else, so the whole of the app's dependence on livekit_client's internals is
/// these few lines.
///
/// WHAT BREAKS IF THE PACKAGE CHANGES, and it is worth being blunt because a
/// deep import is a deliberate cost somebody else will pay. A livekit_client
/// upgrade that renames or moves `SignalJoinResponseEvent`, `Room.engine`, the
/// signal emitter, or the generated proto does not degrade this feature — IT
/// BREAKS THE BUILD. `flutter analyze` and every compile fail on these imports,
/// so the upgrade stops dead at the gate rather than at release. That is the
/// GOOD failure and it is the whole reason this is a compile-time import rather
/// than a reflective lookup, but it means budgeting for it when planning any
/// livekit_client bump: expect to fix this file, and expect the version bump PR
/// to be red until you do.
///
/// The bad failure is silent: if a future version stops emitting the event, or
/// emits it before this can subscribe, [onStamp] is never called at all. There
/// is then NO ANCHOR — not a coarser one. Do not confuse this with a server
/// that sends no `joined_at_ms`, which is a different failure with a different
/// outcome: there the event DOES arrive, carrying a zero, and the caller falls
/// back to the coarse seconds reading in the same frame. Nothing arriving and
/// something arriving empty look alike from a distance and are not alike here.
///
/// No anchor is the deliberate outcome rather than a gap to be patched, and it
/// is worth knowing exactly what it costs, because it is NOT that the halves
/// stop being interleaved. They still are: `TranscriptView.clockShiftFor` is
/// zero for every half when the clocks cannot be reconciled, so the two are
/// merged on RAW device wall clocks that may disagree by minutes, and a reply
/// CAN still render above the question it answers. What is withheld is the
/// TIMES — see `TranscriptView.turnsShareOneClock` — so no reader is shown a
/// printed clock that makes a wrong order look measured. The ordering risk is
/// real and nothing here fixes it.
///
/// What that still buys is the reason not to paper over a silent break:
/// anything that reconstructs an anchor from readings taken at two different
/// moments measures how long that device's connect took, not the disagreement
/// between two clocks, and it would put a confident printed time on top of the
/// wrong order — see `CallMedia.anchorClocksTo`. Fix a silent break by making
/// the event arrive again, never by manufacturing a pair somewhere else.
///
/// If livekit_client ever exposes the field properly — a `joinedAtMs` getter on
/// `Participant`, or the `ParticipantInfo` behind it — delete this file and
/// read it off the participant in `CallMedia`. Nothing else imports it.
///
/// [onStamp] is handed the values the SERVER sent, not values this function has
/// judged. Zero is the ordinary reading for a server that never set the
/// millisecond field: proto3 does not put default values on the wire, so
/// "absent" and "zero" arrive identically and neither is a time. Deciding what
/// to do about that is the caller's, and it is decided in one place — see
/// `CallMedia.anchorClocksTo`.
///
/// The caller should read its OWN clock inside [onStamp] rather than later. The
/// anchor is a PAIR, and it is the difference between the two halves that moves
/// a speaker's turns, so a device reading taken at some other moment folds
/// whatever happened in between into the offset.
///
/// Reading it here is the closest this app can get, NOT the same instant the
/// frame arrived. livekit_client emits on `StreamController.broadcast(sync:
/// false)`, so this runs in a later event-loop turn than the socket read —
/// ordinarily the very next one, and bounded by nothing when the isolate
/// stalls. `CallMedia.anchorClocksTo` carries the full account of what that
/// costs and why it cannot be detected from one observation.
///
/// Fires again on a full reconnect, which sends a fresh join response. The
/// caller latches the first reading it can use; this makes no attempt to
/// choose for it.
///
/// Returns the canceller for the subscription. Cancelling is tidiness rather
/// than a leak fix — the subscription belongs to the room's own signal emitter
/// and dies when the room is disposed.
CancelListenFunc watchSfuJoinStamp(
  Room room,
  void Function(({int secondsMs, int ms})) onStamp,
) => room.engine.signalClient.events.on<SignalJoinResponseEvent>(
  (event) => onStamp(sfuJoinStampsOf(event.response)),
);

/// BOTH join stamps inside one join response, in milliseconds.
///
/// Both, from the SAME frame, because that is what lets the caller check one
/// against the other without reaching for a second source. `secondsMs` is field
/// 6 scaled the way livekit_client scales it for `Participant.joinedAt`, so it
/// is the value the caller would otherwise read off the participant — only
/// earlier, and beside the finer reading it is meant to refine.
///
/// Split out from the subscription above because this is the part a test can
/// reach and the part that can be silently WRONG. `joined_at` and
/// `joined_at_ms` are both int64 on the same message, so reading the coarse one
/// where the fine one was meant compiles, runs, and produces a plausible number.
/// The subscription cannot be reached from a unit test at all: emitting a join
/// response on a real room's signal emitter wakes livekit_client's own handler
/// for it, which builds peer connections through a platform channel.
///
/// `participant` is this device's own entry in the join response, so the stamps
/// are for OUR join rather than the peer's. It is a default, all-zero message
/// when the frame carried none, which is why this returns zeros rather than
/// throwing on a truncated one.
@visibleForTesting
({int secondsMs, int ms}) sfuJoinStampsOf(JoinResponse response) => (
  secondsMs: response.participant.joinedAt.toInt() * 1000,
  ms: response.participant.joinedAtMs.toInt(),
);

/// ONE participant's join stamps, beside the identity the SFU named them by.
///
/// The identity travels with the stamps because these describe devices this
/// code has no other handle on. [sfuJoinStampsOf] answers about US and needs no
/// key; this answers about whoever the frame described, and a reading nobody
/// can attribute orders nothing.
typedef SfuParticipantStamps = ({String identity, int secondsMs, int ms});

/// The shape of [watchSfuParticipantStamps], so a caller can accept it as a
/// seam.
typedef ParticipantStampWatch =
    CancelListenFunc Function(
      Room room,
      void Function(List<SfuParticipantStamps> stamps) onStamps,
    );

/// Every join stamp the SFU states about anyone in this call, ours included, in
/// MILLISECONDS, read off the signalling as it arrives.
///
/// SEPARATE FROM [watchSfuJoinStamp] rather than folded into it, and the
/// separation is a safety property rather than tidiness. That watch feeds the
/// clock anchor, whose two halves have to be read at the same instant, so it
/// may only fire on a frame carrying a FRESH join — the join response. The
/// stamps here also arrive on participant updates, which restate a join that
/// happened at some earlier and unknowable moment; pairing one of those with a
/// device clock read now would measure the time since that join rather than the
/// disagreement between two clocks, which is the exact failure
/// `CallMedia.anchorClocksTo` describes. Keeping them apart means no edit to
/// this watch can reach the anchor.
///
/// TWO EVENTS, because there are two ways a device becomes visible.
/// `SignalJoinResponseEvent` carries `participant` — us — and
/// `other_participants` (field 3), which is everyone already in the room when
/// we arrived. A device that joins AFTER us is delivered by
/// `SignalParticipantUpdateEvent`. Those are the two sources livekit_client's
/// own `Room` builds its remote participants from in an ordinary call —
/// room.dart:548 walks `other_participants`, room.dart:397 hands every update
/// to the same builder — so short of the room move excluded below, a device
/// this app can see at all is a device that came through one of them. Both are
/// emitted on this same signal emitter, at signal_client.dart:280 and
/// signal_client.dart:295, and both carry the `ParticipantInfo` this reads.
///
/// TWO SUBSCRIPTIONS rather than one listener switching on the event type, and
/// the reason is that [joinStampWatchCount] is the only observation a unit test
/// has of what this attached. Two subscriptions make a dropped half show up
/// there as a count; one switch would hide it. Neither event can be delivered
/// through a real `Room` in a unit test: livekit_client's own join handler
/// builds peer connections through a platform channel, and its update handler
/// waits ten seconds for a `RoomConnectedEvent` no unit test can produce, once
/// for every participant the update names (room.dart:785).
///
/// NOT subscribed: `SignalRoomMovedEvent`, which carries participants of its
/// own and is livekit_client's third route into the same builder
/// (room.dart:663). Moving a participant between rooms is a server-initiated
/// LiveKit feature this app never asks for — its call tokens are issued per
/// room — so subscribing would add surface nothing here can exercise.
/// `SignalReconnectResponseEvent` carries no participants at all, so a resume
/// restates nothing and there is nothing there to read.
///
/// What is handed over is what the SERVER sent, in arrival order, and this
/// keeps no memory between calls: it reports statements, and holding them is
/// the caller's. Zero is the ordinary reading for a server that never set the
/// millisecond field, for the same proto3 reason [sfuJoinStampsOf] carries.
///
/// Returns one canceller for both subscriptions.
CancelListenFunc watchSfuParticipantStamps(
  Room room,
  void Function(List<SfuParticipantStamps>) onStamps,
) {
  final events = room.engine.signalClient.events;
  final cancels = [
    events.on<SignalJoinResponseEvent>(
      (event) => onStamps(sfuParticipantStampsOf(event.response)),
    ),
    events.on<SignalParticipantUpdateEvent>(
      (event) => onStamps(sfuParticipantStampsOfUpdate(event.participants)),
    ),
  ];
  return () async {
    for (final cancel in cancels) {
      await cancel();
    }
  };
}

/// One participant's stamps, as the SFU stated them.
///
/// The same two fields [sfuJoinStampsOf] reads, off the same message type, and
/// silently wrong in the same way if they are confused: `joined_at` (field 6,
/// whole SECONDS) and `joined_at_ms` (field 17) are both int64 on
/// `ParticipantInfo`. `secondsMs` is scaled the way livekit_client scales
/// `Participant.joinedAt`, so a caller holds the reading it would otherwise get
/// off the participant beside the finer one meant to refine it — and both out
/// of the same frame, so one can be checked against the other without reaching
/// for a second source.
@visibleForTesting
SfuParticipantStamps sfuStampsOf(pb.ParticipantInfo info) => (
  identity: info.identity,
  secondsMs: info.joinedAt.toInt() * 1000,
  ms: info.joinedAtMs.toInt(),
);

/// Everyone a join response describes: this device, then everyone already in
/// the room when it arrived.
///
/// Ours is in the list rather than left to [sfuJoinStampsOf], because ordering
/// two devices needs both sides read under one rule, and the coarse half of
/// each pair has to come out of the same frame as the fine half it refines.
///
/// A frame carrying no participant yields the default, all-zero message — an
/// entry naming nobody, holding a reading that already means "not said" —
/// rather than a throw. This runs inside `Room.connect`, on a frame nothing has
/// validated, and an exception here would fail a call whose audio was about to
/// work perfectly well.
@visibleForTesting
List<SfuParticipantStamps> sfuParticipantStampsOf(JoinResponse response) => [
  sfuStampsOf(response.participant),
  for (final other in response.otherParticipants) sfuStampsOf(other),
];

/// The same reading for the participants a later update names.
///
/// This is the half that makes the seam cover the whole call rather than only
/// the moment this device came in: a device that joins after us is never in any
/// join response we saw.
///
/// An update also restates devices already known, and says so about ones that
/// have LEFT — livekit_client reads `state == DISCONNECTED` off these same
/// messages. Neither is filtered. A stamp is a statement about when the SFU saw
/// that identity join, which is no less true for the device having gone since,
/// and a reader that cares about presence has the roster for it.
@visibleForTesting
List<SfuParticipantStamps> sfuParticipantStampsOfUpdate(
  List<pb.ParticipantInfo> participants,
) => [for (final info in participants) sfuStampsOf(info)];

/// How many of this file's watches are attached to [room]'s signal emitter.
///
/// Exists so a test can pin WHEN the watches are attached without importing any
/// of this file's internals itself. The device half of the clock anchor is only
/// contemporaneous with the SFU half if the subscription is already live when
/// the join response lands, and that same frame is the only one guaranteed to
/// name the devices already in the room. Both are properties of the ATTACH
/// SITE, not of anything the callbacks do — so a test that only exercises a
/// callback cannot see them, and a regression that moves an attach later passes
/// silently. This is the cheapest honest look at the attach site available: a
/// real `Room` can be built in a unit test, but neither signal frame can be
/// delivered through one, for the reasons [watchSfuParticipantStamps] sets out.
///
/// It counts EVERY subscription on that emitter, not only ours: livekit_client
/// registers its own logging listener there when the `SignalClient` is built,
/// so a fresh `Room` already reports one. A caller must therefore compare
/// counts across the construction it is pinning rather than expect a number.
@visibleForTesting
int joinStampWatchCount(Room room) =>
    room.engine.signalClient.events.listeners.length;
