---
description: "Client call behaviour — presence authority, what ends a call, rejoining, call history, and where audio is tapped."
applyTo: "lib/routes/chat/calls/**,pangea_packages/pangea_call_capture/**,lib/widgets/matrix.dart,ios/Runner/Info.plist,pubspec.yaml"
---

# Voice & Video Calls — Client

Why calls exist, the UX goals they serve, the rollout, the analytics contract,
consent, and pricing are the org doc's:
[voice-video-calls.instructions.md](../../../.github/.github/instructions/voice-video-calls.instructions.md).
Read it first. This doc is what the client implementation commits to, and what a
change to it has to argue against.

## Where the call lives

A call is a LiveKit room joined by two Matrix users, announced through MatrixRTC
member state. Messaging is unaffected: a call is a layer over the room, never a
mode the room enters.

**A call outlives any screen showing it.** It is owned by
[`MatrixState`](../../lib/widgets/matrix.dart), above the router — not by a page.
A page that owned the call hung it up when the page was disposed, which made
leaving the chat during a call impossible by construction. Whatever is showing the
call registers as its presenter, and
[`GlobalCallTile`](../../lib/routes/chat/calls/global_call_tile.dart) renders the
floating tile exactly when nothing else is presenting — so the call is always
visible somewhere and never twice.

**The call id is the room id.** One direct-message room holds at most one live
call, so the id can never distinguish this call from the last one in the same
room. Anything that needs to tell two calls apart uses membership expiry and event
timestamps, never the id. This has cost us the same bug twice — a stale row from an
earlier call dismissing a live ring — so treat any new comparison on call id as
wrong by default.

**Ringing is a timeline event, not member state.** State changes do not fire push
rules, so a ring that lives in state cannot reach a closed app or a second device.
Declines point back at the ring they answer. Ring lifetimes follow what element-web
ships rather than the MSC text: agreeing with the peer matters more than agreeing
with the spec.

## The SDK pin

`matrix` resolves to [our matrix-dart-sdk fork](https://github.com/pangeachat/matrix-dart-sdk)
at a **specific commit**, not a version range, because calling depends on VoIP
internals with no public API contract:

- Advance the pin only for a named, merged fix — never as routine dependency
  hygiene, and never to the fork's HEAD "to pick up latest".
- Restoring a semver range re-opens the drift the pin exists to prevent, so a
  dependency sweep that "fixes" the commented-out `matrix: ^4.1.0` line is wrong.
- A test locks the shape of the SDK VoIP surface the feature depends on, so an
  incompatible SDK change fails in CI rather than at runtime.

## Who is authoritative

Two sources say who is present, and they disagree on purpose.

- **The SFU roster** answers immediately, and is the prompt way a crash is noticed.
  It also keeps a departed participant listed through its own retention window, so
  it cannot be trusted alone to say somebody left, and a re-reported participant
  has to hold for three seconds before it counts as a return.
- **Matrix member state** is the record of intent. Leaving rewrites the member
  event to an empty memberships list. On a homeserver with working delayed events
  the server writes that same retraction on a dead device's behalf, so the
  retraction alone does not say a departure was deliberate — its TIMING does. A
  retraction that lands with the departure was a decision; one that arrives later
  is the server cleaning up.

Two rules follow:

- **An empty memberships list is an ANSWER, not an absence of one.** "No opinion"
  means never having seen the peer write state at all, and the reads are
  three-valued for exactly that reason: absence of evidence is not evidence.
- **Nothing waits on an event that may not come.** Presence is re-derived on a
  short self-clock beside the roster's notifications.

## What ends a call

| Cause | What happens | Why |
|---|---|---|
| They pressed end | Over for both sides at once | The retraction lands with the departure; offering to reconnect is a promise nobody is coming to keep |
| They vanished (refresh, crash, tunnel) | Their place is held for a grace window, then the call ends | The only case the grace window exists for |
| They declined, or the ring expired | Kept distinct from a failure | The caller is owed the reason |
| We pressed end, or our connection is gone for good | Over immediately | — |

Widening the grace window to cover the deliberate case is a regression, however
reasonable it sounds.

A ring arriving while we are already in a call is declined automatically and says
why, so the caller gets an engaged tone and their history reads "busy" rather than
"missed" — except from the room we are ourselves calling, which is glare rather
than a second call.

## Glare, and the clock it is judged in

Both sides can call at the same moment. Glare is judged in ONE clock, and that
clock is ours: did their ring reach us while we were placing ours, within a few
seconds of our own start. Comparing our start against their device's stamp, or the
server's, is a comparison across clocks that no skew allowance makes sound — a
device two minutes fast saw glare where the other side saw none, and one call was
written to the room twice.

## Coming back

A device that vanishes mid-call leaves a breadcrumb behind, and a restart reads it
first:

- **Written** from the moment the call becomes a conversation, per account, so one
  learner's two accounts cannot resume each other's call.
- **Erased** by a clean teardown, and KEPT by a failed attempt to return — so a
  surviving breadcrumb means this device died in a call.
- **Bounded**: a restart slower than a minute and a half gets nothing from it. A
  device whose local storage did not survive falls back to scanning member state,
  which finds the call but not what kind it was.

The offer to return is a promise that there is something to return to, so it is
watched: once the room's state says nobody else is holding the call, it withdraws
itself and takes the breadcrumb with it. Refusing the offer ENDS the call — it
retracts the standing membership, so the other person stops waiting rather than
watching a grace window run out for someone who already decided.

**A returning device always re-announces.** Reusing the membership still standing
in state skips the session refresh, leaves the server's pending delayed leave
armed, and the other side hangs up on a live call seconds later. The call's
identity and the membership currently carrying it are two different things, and
only the first survives a rejoin.

The clock a rejoined session shows continues the call rather than restarting. The
two sides read their own local starts, so they agree to within however differently
the SFU delivered one roster change, not exactly.

## What the conversation records

A call leaves at most one card in the timeline — exactly one whenever either side
survived it — and the chat list says the same thing in the same words. The one call
that leaves none is named below.

**One card, one writer.** The placer writes it; simultaneous placers are settled by
comparing user ids; and the card's key is the caller's membership event id, which
both sides know. If the writer dies mid-call, the other side waits, re-reads the
timeline, and writes the card only if none arrived — and it writes the outcome IT
saw, never an assumption. A call both people reloaded out of writes no card at
all: neither side is the placer. That falls short of the org doc's promise that a
completed call leaves one entry, and is tracked as a v1 gap rather than accepted as
the design — a server-side reconciler is the real answer.

Two durations exist deliberately:

- **Talk time** — the card and the analytics — excludes the gaps where nobody could
  be heard.
- **Call length** — the on-screen clock and the post-call summary — is the number
  the learner just watched.

## Where the audio is tapped

The org doc's attribution rule — each participant's own speech counts toward their
own analytics — constrains where audio can be captured. It has to be THIS device's
own outbound audio, taken after echo cancellation: capture it earlier and the
peer's voice, coming back out of the loudspeaker, is transcribed as the wrong
learner's speech. [`pangea_call_capture`](../../pangea_packages/pangea_call_capture/)
exists because that tap point is platform-specific — Android taps post-AEC
natively, other platforms tap a renderer already downstream of it.

Recording is gated on somebody being able to hear:

- Not while ringing, not during a peer's grace window, not while the connection is
  down — crediting those would put speech in a learner's analytics that nobody ever
  heard.
- Mute gates the recorder in its own right, so a muted stretch is a gap in the
  transcript rather than words recorded anyway.
- One device PER ACCOUNT records, elected among that account's own devices, so a
  learner signed in twice does not transcribe the same speech twice.

Both parties record their own outbound audio simultaneously; that is the whole
attribution design.

Which means a device records its own noise floor for every stretch the OTHER
person is talking, and a chunk that is mostly noise is not merely a wasted
request: measured on a real call, both providers invented words for the silence
and returned a fraction of what was said. So a chunk is narrowed to the part
somebody spoke before it is sent, and a chunk with no speech in it is not sent at
all — captured, held back, and counted as neither transcribed nor lost. See
[call-silence-trim-design.instructions.md](call-silence-trim-design.instructions.md)
for what the detector decides on and which of its numbers are still unvalidated.

## Failure is not all-or-nothing

A call fails only when the call cannot happen, and the microphone is where that
line sits: **no microphone is no call.** Everything the product does with a call —
the conversation itself and the attribution above — depends on the learner being
heard. Whether a device with no microphone should instead get a listen-only call is
an open product question, tracked in Future work, not a settled decision.

Everything else degrades rather than fails:

- A camera that will not open is a degraded call, not a failed one.
- A local participant that never materialises is reported on screen as the other
  person not being able to hear, rather than dropping the call.
- Losing the recording costs analytics and leaves the conversation untouched, which
  is the right way round.

## Platform gates

- **Android** — a foreground service with an ongoing-call notification holds a
  backgrounded call. Both the app and the platform can start or stop it, so every
  instruction carries the generation of the call it was issued for and the platform
  adjudicates: a stop meant for a call that already ended cannot touch its
  successor. Microphone permission is required for a call to start at all.
- **iOS** — the audio background mode in `Info.plist` holds it. `voip` belongs with
  CallKit, which is not built.
- **Web** — no foreground-service concept; the call ends with the tab.

Neither platform can ring a closed app yet, which is the largest gap in the
feature.

Call buttons are built behind a MatrixRTC focus lookup, so an environment without
one renders nothing rather than buttons that fail. This is also what keeps calling
dark on a deployment whose SFU is not running.

## Future work

- [pangeachat/.github#410](https://github.com/pangeachat/.github/issues/410) — the
  v1 follow-up checklist, categorised there by reachability, multi-device, missing
  call history, recording, and Android device-level details.
