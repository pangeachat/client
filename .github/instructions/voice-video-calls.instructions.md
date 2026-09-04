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

**Call media is not end-to-end encrypted, and that is a decision rather than
an omission.** Pangea rooms are created unencrypted and MSC4143 forbids
MatrixRTC encryption in an unencrypted room, so encryption is switched off
explicitly and no key provider is supplied. Transcription does not depend on it
either way — each device transcribes its own outbound audio — so enabling it
later is a change to the room model, not a flag. What the SFU can therefore
see, and what has to be disclosed for it, is the org doc's.

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
| We left the room, on this device or another | Over immediately | A call cannot outlive the room it is in; leaving goes straight to the SDK and knows nothing about calls, so nothing else would stop the microphone |

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

Before recording starts, the call says that it is transcribed and saved and that
both people can read it afterwards. The notice describes what happens to the
words rather than only that they are counted, because knowing that is what makes
capturing the other speaker's audio legitimate. Retention terms are the org
doc's.

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

## What the transcript says

A transcript is ASSEMBLED, not recorded. Each device transcribes the audio it
captured — its own microphone, per the tap above — and writes one event, its
half; a reader merges the two. Both halves hang off the caller's membership
event, which is the one id both sides know from the moment the call starts. The
call card is not that anchor: only one side writes it, and a call both people
reloaded out of leaves none, which would strand the other half in exactly the
case a transcript is most wanted.

A half is one event or it is missing, never a series of parts. Parts need a
sequence that survives process death across a rejoin, and leave no answer for
what "absent" means while more may still arrive.

### Three states, and the distinction that is not one

Somebody opening a transcript is asking whether a conversation happened, so
"they said nothing", "their words are missing" and "we stopped reading early"
stay three different answers. Collapsing them is how a transcript lies. Silence
is deliberately NOT a fourth state — a silent half is a complete, trusted
record, and a state of its own would file it beside "we could not find out" —
but it is the most dangerous distinction in this feature to get backwards, so it
is asked in one place rather than re-derived at each screen.

Two rules keep that honest:

- **Absence is concluded only from an exhausted read of a KNOWN participant
  list.** A read that stopped at our own ceiling proves nothing, and a call whose
  participants we were guessing at cannot be called whole either: the name we
  failed to guess is precisely the one whose half gets dropped, and the screen
  would then show one side of a conversation and say nothing was missing.
- **Our own failures are never reported as facts about them.** A microphone that
  never opened, audio captured and then lost, words dropped to fit the event, an
  entry we could not parse — each is named, and named as ours. "It said I said
  nothing" is unanswerable if all we kept was the state.

Who was on the call is derived locally from the direct chat, and only those two
get a section. The card names a caller, but anybody can write a card, and a
section for a name that was never on the call lends a forgery the standing of a
record.

### What a turn's time promises

A position is known to one of three resolutions, and the screen says which:

| Shown | What the writing device vouched for |
|---|---|
| `m:ss` | the provider timed this turn's first word |
| by `m:ss` | only the chunk of audio bounds it |
| no time | it never said which of those two this is |

A bounded turn is placed at the LATEST moment it could have been spoken, not at
its estimate: an estimate can render a turn a whole chunk early and put an
answer before its question, while the end of the audio it came from cannot place
any turn earlier than it was said. A position whose writer never characterised
it keeps its place in the order — there is nothing else to order it by — and
gets no time printed, because printing one puts this app's confidence behind
another device's silence.

Word timings are estimates, and neighbouring estimates disagree. A small overlap
between two words is measurement jitter rather than disorder; a large one still
refuses the chunk. Reading jitter as disorder costs a whole chunk its timings and
collapses its turns onto a single moment, which is the reordering this section
exists to prevent.

### The clock both halves are merged in

Each half is stamped from its own device's wall clock, and a constant skew shifts
that speaker's ENTIRE side, so the transcript states the wrong person spoke first
and looks ordinary doing it. Each half therefore records its join on two clocks,
the SFU's and its own, and the reader subtracts the difference before merging.
The SFU is the one clock both devices observe. The event's server timestamp is a
RECEIVE time, so a half that took five seconds to send would read as five seconds
of skew, and correcting by it would invert an order that was already right.

Within a device the wall clock is read once per call and every gap after that is
measured monotonically, because a wall clock is not for measuring an elapsed
interval: reading one per stretch of capture turned every clock correction during
a call into a fabricated gap, and bounding that in one direction only left a
forward nudge free to stamp the next stretch arbitrarily late.

The cross-device correction is all-or-nothing across a call: moving one half by
an offset measured for only that half is as likely to harm as to help. It is also no finer
than the join time the SFU publishes, which is whole seconds — minutes of skew
go, about a second remains, and two turns spoken less than a second apart are not
separated by it.

### The words are the transcript's; the timings only say when

Segment text comes from the provider's transcript, and its word list supplies
nothing but the when. Providers return a punctuation-free word list beside a
punctuated transcript, so text assembled from the words loses the punctuation the
learner reads and matches the transcript on almost no chunk. Timings are used
only where they line up with that text word for word, which is what refuses a
provider that re-cut the boundaries — the one failure that could genuinely put a
word in a speaker's mouth. On any disagreement the transcript's own text still
stands and only the precision of the time is lost, so no word a speaker did not
say can reach the screen.

### Reading it back

A finished call reads the way the chat it came from reads: your turns on one
side, theirs on the other, their name once at the top of a run, and a time on
every opening turn — the one thing a chat bubble does not already say, and the
one thing a transcript is for. When ANY half cannot be placed, the call falls
back to per-speaker sections rather than showing part of it in order and part of
it not.

Per-turn times are shown and gaps are not drawn. Anyone can subtract two times
and recover a pause, which is accepted; deliberately presenting the pause is a
different act. Per-word timings are never persisted — one position per turn is
kept, and it is the number that turn's boundary was already chosen on.

## Which language a half is transcribed against

A call has no language of its own, and asking for one is a bug. It has two halves,
and a half has one speaker, one microphone, one publishing account and one analytics
ledger — so the language pair belongs to the account that publishes the half, which is
`room.client`: the same account the call service and the analytics sink are resolved
from, and the account stamped on the half as its sender. Not whichever account is
foregrounded when the call starts, and not the other participant's.

Two learners studying different languages therefore have their halves transcribed
differently, and that is the point: their speech is credited to two separate ledgers
in two separate languages.

The target language is not a soft hint. Choreo picks the whole provider fallback chain
from it, constrains Deepgram's detection to it, and discards any transcript whose
script does not match it — so the wrong pair returns nothing rather than something
approximate, and a speaker who speaks outside their own target language gets an empty
half. That is a settings problem and it is what the E2E harness refuses a run over;
resolving the pair per-account does not and cannot fix it.

The pair is captured once, when the call starts, and never re-read: a learner who
changes their target language mid-call would otherwise have one call transcribed
against two languages and the halves would disagree.

There is one `UserController` for the process and its cached profile follows the
foregrounded account, so the call path reads the room's account data directly instead
of through it. That read is deliberately read-only — the profile getter's legacy path
also SAVES the migrated blob, onto the foregrounded account, and placing a call is not
a settings edit. A per-account `UserController` is the larger fix and is Future work.

## Failure is not all-or-nothing

A call fails only when the call cannot happen, and the microphone is where that
line sits: **a microphone that will not open is no call.** Everything the product does with a call —
the conversation itself and the attribution above — depends on the learner being
heard. Whether a device with no microphone should instead get a listen-only
call is an open product question, not a settled decision.

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

They are also disabled until a second person has JOINED the room. A direct message
whose invitee has not accepted the invite has only the caller in it, so a call
would ring nobody and the caller would sit through a no-answer timeout with no idea
why. The greyed button is that signal, where a silent dead call is not; it comes
back live on the join that brings the second person in.

## Future work

- [pangeachat/.github#410](https://github.com/pangeachat/.github/issues/410) — the
  v1 follow-up checklist, categorised there by reachability, multi-device, missing
  call history, recording, and Android device-level details.
- [pangeachat/devops#348](https://github.com/pangeachat/devops/issues/348) — the
  `Permissions-Policy` header that keeps web video dark.
- [pangeachat/2-step-choreographer#3106](https://github.com/pangeachat/2-step-choreographer/issues/3106)
  — call-condition audio in the speech-to-text gold corpus, which is what would
  put a number on how well either provider reads a call.
