---
description: "When two of a learner's devices end up in the same call: both go silent, the learner picks one, and the other leaves — plus the per-device transcript keying that has to land first."
applyTo: "lib/routes/chat/calls/**"
---

# Two Devices, One Call — Client

An extension of [voice-video-calls.instructions.md](voice-video-calls.instructions.md). Read that first: presence authority, what ends a call, mute's effect on the recorder, and how a transcript is assembled all belong to it. The places this doc changes it are named at the end.

## The first prerequisite: two devices' transcript halves destroy each other

**A transcript half is keyed by USER today, so two devices of one account in one call destroy each other's half. Nothing in this design may ship before that is fixed.**

[`CallTranscriptContent`](../../lib/routes/chat/calls/call_transcript_event.dart)'s transaction id is built from the call key and the sender, and the sender the writer is handed is `room.client.userID` — the account, not the device. Whether the second send is refused by the homeserver or lands as its own event does not matter, because the loss happens one layer later and is certain either way: [`assembleTranscript`](../../lib/routes/chat/calls/transcript_assembly.dart) groups candidates by sender, keeps exactly one per sender — the one with more text — and presents it with its own accounting, which says it is complete. A second device's half is dropped and the survivor claims to be the whole of what that person said.

That is worse than a refused send, which would at least be visible. And it is live in v1 the moment any two devices of one account are both recording, which mixed-version rollout guarantees.

**The fix is one change in three places, and ALL THREE HAVE TO LAND TOGETHER. Any two of them without the third leave the loss exactly where it is.**

| Where | Change | Alone, it fixes nothing because |
|---|---|---|
| The event — `CallTranscriptContent.toJson` | One new optional field: the writing device's id. Absent on every half written before it, and on any foreign client's. | The reader still groups by sender and still keeps one, so the field is written and ignored. |
| The transaction id — `CallTranscriptContent.txnId`, and the `senderId` its call site passes in [`CallSession`](../../lib/routes/chat/calls/call_session.dart) | Scoped to `(call key, sender, device)`. | Two halves reach the room and the reader still discards one. The id only ever governed whether a resend collapses; it never governed the read. |
| The reader — the `bySender` grouping in `assembleTranscript`, and the `_beats` rule under it | Halves grouped by sender AND device; within one device `_beats` still chooses between copies, across an account's devices they are MERGED. | With no device field on the wire there is nothing to group by, so every half from that account keys to the same absent value and the reader is back where it started. |

Scoping the transaction id takes nothing away: the id exists so a RESEND collapses instead of writing a second copy, and a resend is always from the same device. It only stops the id asserting a cardinality it was never entitled to. The merge is sound because each half already carries its own clock anchor, and correcting by it is what already makes two devices' halves mergeable.

**That last clause is a requirement on the writer, not an observation about it. The identity the id is built from is fixed when a publish begins, and every attempt within that publish reuses it.** A retry that reads the identity again can find a different answer — or none, once the client has cleared it — and the homeserver then sees a new transaction rather than a repeat of one it has already accepted. The resend writes a second copy, and the reader, now grouping by device, presents one recording as two devices' worth of speech. That is this section's own loss arriving by the other road: the id collapses a resend only while the resend is still identifiable as one. The same holds for every other value the half's identity is made of, and for the same reason.

**A reader that predates the field does not degrade safely, and pretending otherwise would be the lie.** It sees two events from one sender, keys both to that sender, keeps one, and reports it whole — exactly today's loss, invisibly. That is tolerable only because in the intended path an account writes one half per call, so an old reader sees one half and is right. The case it gets wrong is two UPDATED devices that both carried on — the residual path named below — and that is precisely the case the new reader exists to fix.

**And the fix needs an updated WRITER on each device, not only an updated reader.** Two halves written by two old builds both carry no device field, so they key to the same absent value and the new reader keeps one of them just as the old one did. Nothing about this change reaches a call where both devices are on an old build; only updating one of them does.

Halves are still placed in the two speakers' sections, derived from the direct chat as they are now. A learner-facing per-device label becomes possible once the field exists and is deliberately not in v1: the two halves are the same person and read as one side of a conversation. What v1 does do with the field beyond grouping is record at read time that an account produced halves from more than one device — see the backstop section for why that record is the part that cannot wait.

## The second prerequisite: the signalling plane may not be writable

**This design requires the call token to carry `CanUpdateOwnMetadata`. Whether ours do is unverified, and it is a hard dependency: settle it before implementation starts, not during.**

A claim is a participant attribute, so publishing one is an attribute write, and the SFU refuses that write for a token minted without the grant. `CallRoster`'s announcer already has an error path naming exactly this cause, so the case is real rather than theoretical.

**That calls work today is not evidence the grant is present, and that is the trap.** The recorder election already writes these attributes and already degrades silently without them: silence reads as ABLE, so every device ranks every sibling identically, the device-id order still elects exactly one recorder, and the audio discard simply never fires. A missing grant costs the election its capability ranking and its discards, both invisibly and both in the safe direction. So the one feature that already depends on this grant cannot tell us whether we have it.

**What this design does without it**, stated because the failure would otherwise be silent in exactly the way this doc is careful about everywhere else. No `pangea_chosen` ever lands, so every device reads every sibling as publishing none, and the participation test below then classifies every sibling as unable to take itself out of the call. Every two-device call shows the older-version prompt, on both devices, naming a cause that is not the real one. The only action offered is **Leave the call here**, which needs no write and still works — so a learner can still resolve it by hand, and if they do not, both devices give up at their window and the call ends having written nothing.

**That degradation is safe and is not acceptable as a steady state.** Safe, because it produces silence and a lost record rather than duplicate credit — the direction this feature takes everywhere. Not acceptable, because it would fire on every two-device call and tell the learner something false each time.

**How to settle it: mint a token from the running service and decode the video grant in the JWT.** One call and one decode, not a research project. Partly done already and worth not repeating: the `lk-jwt-service` image contains `canUpdateOwnMetadata`, but only as a field of the LiveKit protocol library's grant struct, which proves the field exists and not that the service sets it.

## During rollout the old bug is still live, and the studies are inside that window

**A device on an older build notices nothing: it does not mute, it does not leave, and it records the whole call.** Nothing this design does reaches it, so the resolution has to come from the updated device, and it does.

**One old device and one updated one still resolves to a single recorder, and the credit stays correct.** The updated device sees a sibling publishing no `pangea_chosen`, mutes, says why, publishes no claim, and gives up at its window — writing no half and no analytics, because it did not carry on. The old device carries on alone. **The cost is that the newer device is always the one that drops out**, whichever one the learner is actually holding, and that a learner who does not read the message gets twenty seconds of silence on it before it goes.

**Two devices BOTH on an older build is the case nothing here reaches.** Neither mutes, neither leaves, both record: the other person hears the learner twice and their analytics count the same speech twice, exactly as today.

**How long that lasts is not something the deploy bounds.** Web picks the change up on a reload, though a stale service-worker bundle can hold an old client past that; iOS and Android pick it up when the learner updates through the store, which is days to weeks and is entirely theirs to decide. There is no version floor on calling and this design does not propose one. **The honest statement is that the duplicate persists for any learner who answers on two devices that are BOTH still on an old build, until they update one of them.**

That window sits inside the WL360 studies (August–November), which are the reason this work exists, so it is a study-data risk and not only a rollout inconvenience. Two things shorten the exposure and both are cheap:

- **Ship the transcript keying on its own, first, ahead of the rest.** It is the smallest of the changes and it needs no other part of this design. It converts one device's half silently destroying the other's into two halves that are both kept, and it stops that silent loss for every call where the writing devices are updated — which is the failure a study cannot detect afterwards. **It does not reach two devices that are both on an old build**: neither writes a device field, so both halves still key alike and the reader still keeps one. Nor does it fix doubled audio or double credit anywhere.

**So nothing in this design reaches a learner whose two devices are both on an old build.** Only their updating one of them does — or a credit backstop, and only one that lives where the analytics land rather than in the client, since an old client would not be running a client-side one either.
- **Confirm study participants' devices are updated before their sessions**, or ask them to answer on one device. This is an operational answer rather than a code one, and it is the only lever that reaches the credit half of this exposure without changing a shared analytics contract mid-study — see the backstop section below for the one that would.

## The problem

A learner signed in on a phone and a laptop hears both ring. Answering on both puts both in the call: both publish audio, so the other person hears them twice, and both record, so they are credited twice for saying something once. The [recorder election](../../lib/routes/chat/calls/capture_election.dart) settles which one keeps recording a second later, but the opening seconds are already captured on two devices, and its own `discardsCapturedAudio` explains why no tiebreak can clean that up afterwards: destroying captured audio needs positive proof that a sibling holds the same stretch, and the join stamp the election compares is accurate only to the whole second, so two devices that answered in the same second are unorderable.

That last clause is about what the ELECTION READS, not about what the SFU can say, and the distinction is now load-bearing enough to write down. The SFU does send a millisecond join stamp -- `joined_at_ms`, proto field 17, observed present and correct on livekit-server v1.9.1 and absent before v1.8.4 -- and the transcript's clock anchor reads it. The election does not. The seam reads every participant the SFU names -- this device out of the join response, the devices already in the room out of its `other_participants`, and later joins off the participant updates -- so a sibling's millisecond stamp is now held rather than discarded. The election now compares at the MILLISECOND wherever the pair supports it. Whether a given comparison may be narrowed is a question about the PAIR rather than about the deployment -- a stamp is millisecond-real only where the server set field 17 for that device -- so it is answered from the two stamps in hand: both halves are taken from the SFU's own statements, or the comparison falls back to `joinStampResolution` and the whole second. A mixed pair, one device behind a server older than v1.8.4, falls back rather than assuming the half it cannot see. The premise above therefore still holds today -- but it holds because of what the election compares at, and a reader who learns the SFU sends milliseconds, or that this app now reads a sibling's, should not conclude it has stopped holding.

**Three design rounds tried to prevent the second device from joining and each failed on the same instant** — when both devices answer at once, neither can see the other on any plane, so any rule evaluated then has one value and settles nothing.

So this design does not prevent. It notices, silences both devices, and asks the person.

### What is narrowed, and what is not closed

**Neither double capture nor double credit is closed by this design. Both are narrowed, and the difference between them is where the defence lives.**

**Double CAPTURE is narrowed to the moment before each device can see the other.** In that window both devices genuinely record. Nothing here prevents it and no tuning will: a device cannot act on a sibling it cannot yet see.

**Double CREDIT is narrowed to the cases where two devices BOTH carry on with the call.** The rule doing the narrowing is that a device which does not carry on writes no transcript half and no analytics, so the audio it captured before muting never becomes a number. That is what stops the ordinary race from double-counting: the capture happened, the credit did not.

**But two devices can both carry on, and then both credit. There are two ways, and this design closes neither:**

- **BOTH devices are on an older build.** Neither mutes and neither leaves, so both record the whole call. Nothing in this design reaches either of them; see the rollout section above. This is by far the larger of the two. One old device and one updated one does NOT belong on this list — that case resolves, because the updated device gives way.
- **Two participating devices both claim and neither ever reads the other's claim**, so both reach the handover fallback and both carry on. It needs the attribute channel to fail in both directions at once, so it is rare — but its cost is a full duplicate of the call's credit rather than a moment of it.

**The transcript keying fix is not a credit fix either.** It stops one half destroying the other; where two devices recorded the same speech it now preserves both, so a duplicate that used to be silently half-discarded becomes visible in the transcript instead. Visible is better than hidden, for a study especially, and it is not the same as fixed.

**And visible is not the same as diagnosable.** A person reading a merged transcript sees repeated text, and repeated text is also what a learner saying something twice looks like. On its own the preserved duplicate cannot tell those apart, so on its own it cannot serve as the trigger for the backstop below. **What v1 adds instead is a reading-time record: when one account's halves for a call come from more than one device, the reader says so**, beside the line it already writes for a half that is not clean. A COUNT rather than the device ids, because every log in this feature keeps participant identity out and the call key already distinguishes the halves of one call, which is all the diagnosis needs. That is what makes duplicate credit countable, and countable is what the trigger actually requires. A learner-facing per-device label is a different feature and stays out of v1; if the studies need a human reading transcripts to spot duplicates by eye rather than a count to find them, the label has to come forward too, and the field is on the wire either way.

**So the analytics are not safe on this design alone.** What would make them safe is a rule at the credit layer rather than the presence layer.

### The backstop this design does not include

Inflated vocabulary counts are exactly the failure a study cannot detect after the fact — a learner credited twice reads as a learner who talked twice — so the residue above matters more than its rarity suggests.

**The lever exists and is not used.** The answering side of a call writes no timeline card and anchors its analytics instead to the ring notification it was called with, which every device that was rung holds. Two devices of one account answering one ring therefore already agree on the anchor, and they are the same Matrix user. "One call, one speaker, credited once" is a rule that could be stated against that anchor.

**It was proposed once and the owner rejected it, correctly, as a REPLACEMENT for fixing the presence problem**: making the credit idempotent would hide the fact that two devices are on the call rather than stop it. That objection is right, and it is not an objection to a backstop. The distinction is the whole point — as a replacement it lets the two-device state persist unnoticed and launders the symptom; as a backstop it sits UNDER a fix that still removes the second device, and catches only the residue that fix cannot reach. The two paths above are precisely what a backstop is for.

One earlier argument against it should not be recycled: that idempotent credit cannot tell the race, where crediting once is right, from a handover mid-call, where crediting both halves is right. **That case does not exist in v1**, which has no way to move a call, so every two-device call here is a race or a mixed-version accident and crediting once is right for both.

**What it would cost is real, and it is why this is not in v1.** `addAnalytics` takes an anchor and a list of construct uses and sends them as an update. It has no per-anchor identity, and nothing dedupes a second send against the same anchor. Giving it one changes the path every analytics writer in the app uses — messages and exercises included — to fix a call bug, on a deadline, with the studies running.

**So v1 ships ownership without a credit backstop and states the residue rather than papering over it.** What would reopen it is evidence from the studies that duplicate credit is actually reaching learners' numbers — which the multi-device read record above is what makes countable, and the reason that record is in v1 rather than deferred with the label. **That record undercounts, and in the direction that matters:** it can only see halves that carry a device id, so it catches two updated devices that both carried on and is blind to two old builds, which is the larger path. A count of zero from it is not evidence of no duplicates. It belongs to the analytics owner and needs its own design; it is named here so that the option is on the record rather than lost with the proposal it was once bundled into. One thing that design would have to settle up front: a backstop in the client cannot help a learner whose devices are both on an old build, so if reaching that case is the point, it has to sit where the analytics land instead.

## What the learner sees

Both devices, the same prompt, because until the learner answers there is no chosen device and no way to tell them apart:

| | |
|---|---|
| **"This call is open on two of your devices."** | *"Pick the one to carry on with. Until you do, neither is sending your microphone or camera."* |
| **Use this device** | This device carries on. The other leaves. |
| **Leave the call here** | This device leaves. The other carries on. |

Then two sentences, each from what that device alone knows:

- The device the learner chose against says **"This call is continuing on your other device."** It never asked to be dropped, so it does not report a failure and it does not say anything moved — nothing did. It does not name the other device either: a device id is not a name, and guessing one would be worse than saying nothing.
- The device the learner chose says **nothing**. The sheet closes and the call resumes with the microphone and camera exactly as the learner had them — a voice call does not come back as a video call, and a learner who had already muted themselves stays muted.

**A device stops offering the choice the moment it can see any claim at all**, its own or a sibling's. That is what keeps a prompt from being answered after the question has been settled elsewhere.

**Against a sibling that cannot take itself out of the call, the choice is a different one, because "Use this device" could not keep its promise.** That device says:

| | |
|---|---|
| **"Your other device can't leave this call on its own."** | *"End the call there, or leave it here. That usually means it is running an older version, and updating it will fix this."* |
| **Leave the call here** | The only action, and it always works. |

Adding options later is adding rows to this sheet, not redesigning the flow. The owner's next step — several devices in one call with different jobs, "stay in the call and use the microphone here, the camera there" — is the same prompt with more than one way to say yes.

## Why the person arbitrates

Every earlier round tried to compute the answer. Each one bought a new failure with it: a rule both devices evaluate can be evaluated on different data at the same instant, so both can conclude they lost and the learner is left in no call; a rule that names a winner has to say what happens when that winner dies a second later; and any rule at all has to be re-derived by a second device that may be running an older build.

**Asking the person deletes all of them.** There is no order to disagree about, no tiebreak, no arbiter, and no way to be wrong: the learner cannot pick the wrong device, because the device they picked is the one they want. What is left is a mechanism for carrying one bit from the device they touched to the device they did not.

## Every step waits for something OBSERVED

**No device ever acts on not having seen something.** This codebase already learned that lesson one layer down. `PeerPresence` is three-valued — live, gone, unknown — and the enum says why in its own words: a retraction or an expiry is "positive evidence of a departure", while having seen nothing is "not evidence of anything", because state lags a join by seconds. The same discipline governs here. "I have not seen a sibling's claim" is not "there is no sibling's claim"; an attribute that has not propagated and an attribute that does not exist read identically.

So the chosen device does not unmute because no rival claim appeared. **It unmutes when it observes its siblings actually GONE from the participant list.** Every transition below is a state somebody can point at:

| What this device can see | What it does |
|---|---|
| No sibling remains — whether or not this device ever claimed | Ordinary call. The prompt withdraws, the give-up timer is cancelled, and the microphone and camera are restored to what the learner had. |
| A sibling, and no claim from anyone | Microphone and camera closed and HELD closed at once. The prompt, once that sibling has been continuously visible for one presence tick. |
| A sibling's claim | Ends here, with the message above, whether or not this device also claimed. |
| A sibling publishing no `pangea_chosen` at all | Stays held. The older-version prompt instead of the choice. No claim, no wait — neither could resolve it. |
| Any sibling still listed | Stays held and waits, claimed or not. |

**The first row is one rule and not two, and that matters.** An earlier draft let only a device that had CLAIMED resume when its siblings went, and left a merely-waiting device's give-up timer running — so a learner who tapped "Leave the call here" on one device, deliberately, to keep the call on the other, watched the other one drop out too a few seconds later. A sibling's departure is positive evidence that the ambiguity is over, whoever claimed what, and **a timer that fires after the thing it was waiting for has happened is doing harm rather than safety.** So the departure resolves the call and cancels the timer, and the rule reads the same for every device.

It cannot resume a device the learner meant to leave: "Leave the call here" ends that device outright, so there is no window in which it is still in the call to observe anything.

Three properties fall out of that table:

- **It generalises to any number of devices with no special case.** The chosen device waits until none of its siblings remain; the others each read the claim and go. Three devices need no more rules than two, and a learner who dismisses one device of three is correctly left choosing between the remaining two.
- **A late tap needs no special case either.** Every row is re-read from the roster on every recompute, so a tap that arrives after the situation has changed is evaluated against the situation as it is then, not as it was when the prompt appeared.
- **"Leave the call here" needs no claim at all.** The device just ends; the others then observe it gone. The departure is the evidence.

**The microphone and camera are HELD closed, not merely set closed, and the prompt's promise depends on it.** The prompt says neither device is sending anything, and the ordinary mute and camera controls would otherwise let a learner reopen either one — on both devices, giving duplicate audio and duplicate credit through the front door, with no race and no propagation failure involved. So while a sibling is unresolved the controls do not open the microphone or the camera, on any surface. That is one gate rather than one per surface: `CallSession`'s own `toggleMute` and `toggleCamera` are where it goes, because the platform's ongoing-call notification is already deliberately routed through the same two methods as the on-screen buttons. The learner's own setting is remembered rather than overwritten, which is what the resolved rows restore.

**Absence from the participant list is not the same kind of absence as a missing attribute, and the difference is what makes this sound.** The list is the SFU's own enumeration of who is in the room, pushed as state and recomputed whole on every notification, and its error runs the safe way: it holds a departed participant through its retention window rather than dropping a present one. A stale list therefore delays an unmute and can never cause an early one.

**What it costs is one more round trip of silence.** After the learner taps, the chosen device stays quiet until the claim reaches the sibling, the sibling tears down, and the departure reaches the roster — a second or two beyond the tap in the ordinary case. The alternative is what the previous draft of this design did: unmute on the strength of no rival claim having appeared, which in a double tap gives the other person doubled audio and then a dropped call, and with three devices unmutes one while another is still there. Silence for a beat is the direction this feature takes everywhere else, and this is not the place to stop.

### This does not depend on knowing a claim landed

The write may fail. **Nothing here needs to know whether it did**, and that is deliberate, because the roster's announcer cannot tell a caller: when a write fails the loop returns and the `finally` releases every outstanding waiter anyway, on the stated grounds that "it is not going to be said" is an answer for the caller that needs one. So a completed announcement means settled, never landed, and a design that waited on that future would be waiting on nothing.

The roster does keep a genuine landed value — the announced map is updated only after a successful write, which is what `announcedCanCapture` exposes for capability — so exposing one for this attribute would be a getter of the same shape and nothing more. **It is not needed and is not proposed.** A device treats itself as chosen because the learner tapped it, not because the write succeeded; and if the write never goes out, the sibling never leaves, and the fallback below is what covers it.

### The bounded wait, and the sibling it must never be applied to

A chosen device whose sibling has not yet read the claim would otherwise wait forever, and so would one whose sibling has genuinely gone but is still inside the SFU's retention window. So **a device that has claimed unmutes anyway once the handover window runs out** — twenty seconds, matched to the SFU's own departure retention, because that is exactly the interval during which a sibling that has actually left may still be listed.

**A bounded wait may only give up into a state it can vouch for**, and that is the constraint that decides who it may be applied to. Giving up assumes the sibling left. Against a sibling that speaks this protocol the assumption is a reasonable bet on propagation, and the invariant behind it holds: such a sibling, seeing us and not having been chosen, is muted. **Against a sibling that CANNOT leave, it is a guaranteed wrong answer** — the wait expires, the device unmutes, and both are live with duplicate audio and duplicate credit until the learner ends one by hand. The valve would restore the exact state it exists to remove.

**So a device that does not speak this protocol is identified, and never claimed against or waited on.** Every device running this design publishes `pangea_chosen` from the moment it joins — `no` until the learner picks it, and only then the claim. That unconditional `no` is the whole discriminator, and it is the same discipline `pangea_capturing` already follows for the same stated reason: publishing while idle is what separates a sibling that has told us something from one we have simply not heard from. **The two existing attributes cannot do this job** — the recorder election already ships, so a device with the election and without this design publishes both of them and would read as participating.

Against a silent sibling, two things follow and both are deliberate:

- **No claim is published and no wait is started**, because neither can resolve anything. The prompt above replaces the choice with the truth.
- **The device stays muted rather than unmuting into a duplicate it can see coming.** Either answer is defensible; this one follows the direction the rest of the feature takes, which `CaptureElection` states for itself: losing credit is recoverable and inventing it is not. Silence is recoverable — the learner ends the other device, leaves the call here, or hangs up and calls back. Inflated study analytics are not. **The cost is real and falls on the learner: if their other device is in another room, they cannot speak on this one until they deal with it.**

**The test is not perfectly sharp, and the blur runs the safe way.** A device that IS updated but whose first `pangea_chosen` write has not landed publishes nothing either and reads identically. Two things bound that. The prompt already waits one presence tick before appearing, which is why that tick does double duty rather than only guarding echoes — it is also the margin the first write has to land in. And reading a sibling's attributes is independent of writing one's own, so a sibling misread this way still reads what it needs from us and still leaves when the learner acts, at which point this device sees it gone and unmutes by the ordinary rule. Being wrong here costs a message naming the wrong cause and the loss of a one-tap resolution. It never costs a duplicate, which is why this is the reading to take.

The residue, stated rather than papered over: if two PARTICIPATING devices both claim and NEITHER ever reads the other's claim, both reach the fallback and both carry on — two live microphones and two sets of credit. It needs the attribute channel to fail in both directions at once. If only one direction fails, the design still lands on one survivor; that row is in the failure table below.

## The plane, and the two that are not used

Detection is the SFU participant list, read through [`CallRoster`](../../lib/routes/chat/calls/call_roster.dart)'s `siblingDeviceIds`.

- It is the timely one. The roster recomputes the whole picture from the participant list on every notification and the call re-derives it on its own clock besides, so a sibling is visible within a second or two of joining.
- It is already the single source of truth for who is in a call, and the recorder election reads it. A rule that disagreed with presence about who is present would silence a device on the strength of a sibling that had left.
- The identity the token service mints carries the device (`@user:server:DEVICEID`), so the roster can already tell one of the learner's own devices from the other person.

**Matrix membership is not used.** `CallService.myDeviceIdsInCall` reads sibling devices from room state and has ZERO callers anywhere in the app or its tests; it is dead code and nothing here revives it. Room state lags a join by seconds and holds a crashed device's entry for as long as `CallDelayedLeave.applyLeave`, so a rule built on it would silence a live device because of a dead one. The one membership read that stays is `answeredOnAnotherDevice`, unchanged, still doing the job it does today — stopping a second device ringing once the first has answered. That already closes most of this problem. What is left, and what this design is for, is the simultaneous answer and the learner who deliberately joins from a second device.

**No new server BEHAVIOUR is asked for.** The token service stays a stateless minter and the identity keeps its device segment — dropping it would foreclose the multi-device presence the owner intends to add. **That is not the same as asking nothing of the server:** the claim needs the token it already mints to carry `CanUpdateOwnMetadata`, which is a requirement on the server whether or not anything there changes, and it is unverified. See the second prerequisite above — it blocks implementation.

The claim itself rides on **participant attributes**, the plane this codebase already uses for exactly this shape of question: `CallRoster` publishes `pangea_can_capture` and `pangea_capturing` this way and reads siblings' values straight off their attributes. A third attribute, `pangea_chosen`, takes the same plane and the same announcer, so there is no new channel and no new failure mode to characterise.

**It does not exist yet, and it is not free.** `CallRoster` today defines only `pangea_can_capture` and `pangea_capturing`, and there is no reader, no field and no announcer for a third. Adding one means the constant, a reader beside `capableFromAttributes` and `captureReportFromAttributes`, a field on `CallParticipant`, **an announcement made unconditionally on joining rather than only when the learner picks the device** — that is what makes silence mean "does not speak this protocol", and it is the whole basis of the participation test above — and, the part that is easy to cost at zero, **that field has to be in `CallParticipant.state`, the tuple the roster's notify predicate is derived from.** A field left out of it changes in silence: the claim would land and no listener would run, so a prompt would sit stale until something unrelated happened to move the picture. That is not hypothetical — the tuple exists precisely because a hand-maintained list of fields worth notifying about once let a capability change land unnoticed.

## Timings

| Step | When | Why that |
|---|---|---|
| Close the microphone and camera, and hold them closed | The first reading that shows a sibling. No confirmation delay. | Closing them is cheap and reversible, and it is the single action that narrows the double capture. Waiting to confirm first would pay for the confirmation in exactly the audio the feature exists to stop. Held rather than merely set, so the ordinary controls cannot reopen what the prompt says is closed. |
| Show the prompt | Once the sibling has been continuously visible for one `ActiveCall.presenceRecheck` tick — two seconds. | Interrupting a conversation is not reversible in the way muting is. The SFU re-reports participants it is still holding, which is why `peerReturnConfirmed` exists at all, so a prompt must not rest on one reading. An echo inside that tick costs a two-second dropout and nothing else: the device unmutes and the learner never sees a prompt. |
| A device that has not been chosen gives up | Twenty seconds after it FIRST SAW A SIBLING, not after the prompt appeared — and cancelled outright the moment no sibling remains, because the departure has resolved what the timer was waiting on. It ends itself. | Timed from detection so there is an exit even when the prompt never appears at all — hung on the prompt, a device that detected a sibling and then failed to show one would sit muted and silent indefinitely, with nothing to end it. The learner gets the remainder after the prompt lands, about eighteen seconds. The length matches `ActiveCall.peerGraceWindow` and the judgement behind it: twenty seconds is already this feature's answer to how long a call may run with one side unheard before ending it is kinder than leaving it open. |
| A device that HAS been chosen stops waiting | Twenty seconds after it claimed, it unmutes regardless. | Matched to the SFU's departure retention, per the section above. |

Both windows are separate constants that happen to share a value, so tuning one does not silently move the other. Everything here finishes far inside `CallDelayedLeave.applyLeave`, so no membership-plane cleanup can ever become an actor in this decision.

**A device that gives up ends only ITSELF. It never ends the call for the account.** If nobody chooses, both devices reach the window and both end, so the call ends — reached without either device instructing the other, which is what keeps a device whose network hiccuped from taking down a call that was resolved correctly elsewhere.

## What the other person hears, and what they are told

They hear silence and the video stops, for as long as the learner takes to choose, plus the round trip above. **That is the accepted cost of this design and it is the whole of it.**

They are not told anything new, because they are already told the true thing. `peerMuted` reads over the peer's participants and is true when every audio publication they have is muted, so with both of the learner's devices muted the other person's screen says the learner is muted — which is exactly what is happening. Muting does not withdraw the publication, so this holds throughout.

The account never appears to leave: `hasPeer` asks whether any participant belongs to a DIFFERENT account, so two of the learner's devices are one peer and one of them going is not a departure.

## What a device that does not carry on does with what it captured

It captured something — the fragment between joining and the mute, under a second in the ordinary case.

**It delivers none of it. A device that does not carry on with the call writes no transcript half and no analytics for it.** That covers both ways of not carrying on: the device the learner chose against, and the device that gave up because nobody chose it. **Both need stating rather than assuming, because teardown normally stops the recorder and then FINISHES the record, which is what publishes the half** — so this is a rule that has to be added at that seam, not one that falls out of leaving.

It is unconditional and needs no proof, because the question is not "did the other device hold this stretch" — which the whole-second join stamps cannot answer — but "did this device carry on with this call", which it knows about itself.

What that costs: the chosen device muted at the same moment, so both fragments cover roughly the same opening seconds, and discarding one is right. Where the two devices' first frames differ, the sliver the discarding device had and the other did not is lost. It is bounded by the difference in media bring-up between two devices answering the same ring, which is expected to be small and is not measured. The alternative — publishing it — double-counts precisely the stretch both devices captured, which is the bug.

The chosen device's own recording carries a gap where it was muted. That is already how mute reads in a transcript, and the run token the recorder publishes is what makes the break visible rather than silent.

## Failure modes this accepts

| Case | What happens | What it costs |
|---|---|---|
| The learner taps on both devices inside the propagation window, and each reads the other's claim | Both end. Neither ever unmutes, because neither sees its siblings gone. The call is over for the account. | A redial. No doubled audio and no double credit. Two taps more than about a second apart resolve correctly, because the second device is already gone and its prompt already withdrawn. |
| Both claim, but only ONE direction of claim visibility works | The device that reads the other's claim ends. The device that does not keeps waiting, observes the first one gone, and unmutes. | Nothing. One survivor, which is the right outcome, reached without either device knowing the visibility was one-way. |
| Both claim and NEITHER reads the other's claim | Both reach the handover fallback and both carry on. | The worst row in this table: two live microphones AND a full duplicate of the call's credit, because both devices believe they carried on, so both finish and both write. It needs the attribute channel to fail in both directions at once. Nothing here catches it — see the backstop section. |
| The unchosen device never sees the claim | It stays muted with the prompt up and ends itself at its window. The chosen device waits, then unmutes at its own. | Up to twenty seconds before the other person hears the learner again. Silence, not doubling. |
| The chosen device's claim never goes out | Same as above, reached from the other side: the sibling never learns and gives up at its window, and the chosen device resumes either on seeing it go or at its own fallback, whichever lands first. | The same twenty seconds. |
| The chosen device dies immediately after the other has left | The call is over for the account; the other person's ordinary vanish path runs. The learner's other device is not in the call and, in v1, has no way back in but a fresh call. | The same as any single-device crash, plus the device that would previously have still been there. This is what a "Move the call here" action would recover, and it is not in v1. |
| ONE device is running a build without this | The updated device sees a sibling with no `pangea_chosen`, mutes, shows the older-version prompt, claims nothing, waits for nothing, and gives up at its window writing neither half nor analytics. The old device carries on alone. | One recorder and correct credit. The cost lands on the learner instead: the NEWER device is always the one that drops out, whichever they are holding, and they get twenty seconds of silence on it if they do not read the message. |
| BOTH devices are running a build without this | Neither mutes, neither leaves, both record. Nothing here reaches either of them. | The old bug in full, for as long as neither is updated. See the rollout section — this is the exposure that matters most and it is not a table row's worth of risk. |
| A participating sibling is misread as non-participating, because its first `pangea_chosen` write is slower than a presence tick | This device shows the older-version prompt and offers no claim. The sibling, whose READS are unaffected, still resolves normally once the learner acts. | A message naming the wrong cause, and the loss of the one-tap resolution. Never a duplicate, which is why the blur is read in this direction. |
| A device sees an echo of a sibling that already left | It mutes and, if the echo persists past a presence tick, prompts. | Up to two seconds of dropout for an echo shorter than a tick; a spurious prompt for one longer. The prompt withdraws itself when the sibling goes, and the give-up timer with it, because every rule here is re-read rather than remembered. |

## What this changes elsewhere

1. **The parent doc's "one device per account records, elected among that account's own devices."** Refined: one device per account is unmuted in the call, and that device records. The election is not retired — it still runs, with one candidate — and removing it is not this change's job.
2. **`discardsCapturedAudio` stops being reachable in the steady state.** Nothing depends on it once no two devices of an account are capturing at once. It stays as defence.
3. **Capability stops deciding anything.** A learner whose chosen device has a broken microphone gets an unrecorded call where the old election would have handed the recording to the other phone. Their recourse is to choose the other device, which is a tap. That is a real narrowing and it is the price of putting the decision with the person.
4. **The parent doc's "a half is one event or it is missing, never a series of parts"** becomes one event per DEVICE, still never parts from one device. A device id is not a sequence and a device writes once.

## Not in v1

- **Several devices in one call on purpose**, with different jobs per device. The prompt is shaped to grow into it; nothing else here is. **This is the one place the design overrules an intention rather than resolving an accident, and it should be read that way.** A learner who deliberately joins on a laptop for its camera and a phone for its microphone — a reasonable thing to want, and something some will try — is treated exactly like someone who answered twice by mistake: both devices are held closed and they are made to collapse to one. There is no way to express the intent and no partial accommodation, so the cost is the whole of it: they use the better camera or the better microphone, not both, until per-device roles exist.
- **A learner-facing per-device label on a speaker's halves**, and telling a reader that a second half should exist. Both are further optional fields on the same event and neither reworks the one added here. What v1 does ship in their place is the read-time record that an account produced halves from more than one device, because the backstop's trigger needs duplicates countable and this is the cheap half of that.
- **Group calls, and a second concurrent call in another room.** Everything here assumes a direct chat holding one call between two accounts. A call placed in a DIFFERENT room while a sibling is in one elsewhere stays governed by the per-device busy rule, which does not see siblings.
- **Getting back into a call the learner chose against.** There is no "move it back". They call again.
- **A minimum client version for calling.** It would close the rollout exposure and it would also refuse calls to learners who have done nothing wrong. Not proposed here; named so the option is on the record.

Tracked with the rest of the v1 follow-ups in [pangeachat/.github#410](https://github.com/pangeachat/.github/issues/410).

## What is not settled from the source

Verified in the pinned SDK and `livekit_client` and safe to build on: the whole-second join stamp, the user-scoped transcript keying and the reader's one-half-per-sender rule, that a failed attribute write still releases its waiters so no landed signal is available from that future, that mute leaves the publication in place so the other person reads it as muted, and that `myDeviceIdsInCall` has no callers.

These are not, and each is cheapest to settle with the two-Chrome harness signed into the SAME account (`pangea-call-testing`):

- **How long the SFU actually takes to show each device the other.** Where both devices are updated, that interval is the whole of the double capture, so it is the number the narrowing claim above rests on. It says nothing about the mixed-version case, where the overlap is the whole call.
- **How quickly a departure reaches a sibling's roster after a clean leave**, which is the silence the learner pays between tapping and being heard again.
- **How quickly a joining device's first `pangea_chosen` write lands, against the one presence tick the prompt waits.** That margin is what separates "running an older build" from "has not published yet", and the participation test — and therefore the older-version prompt and the whole bounded-wait exclusion — is only as sharp as it.
- **How quickly a claim written through the attribute announcer reaches a sibling**, and how stale it can be when it does. Whether it can be written at all is not on this list: that is the second prerequisite, and it is settled by decoding a token rather than by the harness.
- **Whether muting the camera and restoring it leaves a voice call a voice call**, given that the camera toggle already refuses quietly rather than throwing when a call is going away.
