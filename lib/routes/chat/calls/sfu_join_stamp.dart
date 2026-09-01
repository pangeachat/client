// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_client/src/internal/events.dart';
import 'package:livekit_client/src/proto/livekit_rtc.pb.dart';

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
/// consumed inside `Room.connect` without being stored. The signal event is
/// the only place it is reachable at all.
///
/// So this file deep-imports `src/internal/events.dart` for
/// `SignalJoinResponseEvent`, and reads `Room.engine`, which is `@internal`.
/// Both are suppressed at the top of THIS file and nowhere else, so the whole
/// of the app's dependence on livekit_client's internals is these few lines.
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
/// The shape of [watchSfuJoinStamp], so a caller can accept it as a seam.
typedef JoinStampWatch =
    CancelListenFunc Function(
      Room room,
      void Function(({int secondsMs, int ms}) stamps) onStamp,
    );

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
/// How many join-stamp watches are attached to [room]'s signal emitter.
///
/// Exists so a test can pin WHEN the watch is attached without importing any of
/// this file's internals itself. The device half of the clock anchor is only
/// contemporaneous with the SFU half if the subscription is already live when
/// the join response lands, and that is a property of the ATTACH SITE, not of
/// anything the callback does — so a test that only exercises the callback
/// cannot see it, and a regression that moves the attach later passes silently.
/// This is the cheapest honest look at the attach site available: a real
/// `Room` can be built in a unit test, but a join response cannot be delivered
/// through one, because emitting on its signal emitter wakes livekit_client's
/// own handler and that reaches a platform channel.
///
/// It counts EVERY subscription on that emitter, not only ours: livekit_client
/// registers its own logging listener there when the `SignalClient` is built,
/// so a fresh `Room` already reports one. A caller must therefore compare
/// counts across the construction it is pinning rather than expect a number.
@visibleForTesting
int joinStampWatchCount(Room room) =>
    room.engine.signalClient.events.listeners.length;

@visibleForTesting
({int secondsMs, int ms}) sfuJoinStampsOf(JoinResponse response) => (
  secondsMs: response.participant.joinedAt.toInt() * 1000,
  ms: response.participant.joinedAtMs.toInt(),
);
