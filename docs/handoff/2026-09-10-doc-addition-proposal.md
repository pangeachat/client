# Proposed governed-doc addition — call recording playback (PR2)

**Status:** DRAFT for owner (Will) review. NOT applied to the instructions doc.
An instruction-doc edit is never made unilaterally by an agent
(`copilot-instructions.md` invariant). This is the proposal to review.

**Target doc:** [voice-video-calls.instructions.md](../../.github/instructions/voice-video-calls.instructions.md)
(client copy). The org doc is unaffected — this is client implementation design.

## Why this addition exists

PR2 adds behaviour the doc does not yet cover. The existing
"What the transcript says" section governs how the transcript is assembled,
ordered and read; it says nothing about **playing the call back**, because until
PR2 there was nothing to play. PR2 offers the merged recording as a single
"full call" the learner can play, highlights the turn being spoken as it plays,
lets a tap on a turn's time seek to it, and has to show a waiting state while
the recording is still being assembled. New behaviour in a covered area is a
design decision, so it is drafted here for the doc rather than left only in code.

Two things in it are subtle enough to be worth governing specifically: the
**order-by-end / play-from-start asymmetry**, and **when a turn may be sought at
all**. The rest is UX that follows from them.

## Proposed placement

A new subsection **"### Playing the call back"** inside "What the transcript
says", immediately after "### Reading it back". It depends on the two
timing subsections above it ("What a turn's time promises", "The clock both
halves are merged in"), so it reads best after them.

## Proposed text (in the doc's voice)

---

### Playing the call back

The two halves are also mixed into one recording of the whole conversation, and
that merged recording is what the learner plays — one "full call", not two mono
files to reconcile by ear. The per-device halves stay reachable beneath it,
because the merge is not always complete and a learner may want the raw half
that is there.

**A turn is ordered by the end of its audio but played from the start of it.**
Those are two different instants, and the transcript already keeps both: the
turn is placed in the reading order at the latest moment it could have been
spoken, so an answer never precedes its question, but that placement is the
wrong place to begin playback — the words began earlier, at the turn's own
start. So each turn maps to a window in the recording that opens at the turn's
start and closes at the chunk boundary the order was chosen on. The start plays
the audio; the end keeps the order.

That window is expressed against the merged recording's own timeline, which
begins at the earliest half's join on the shared SFU clock — the same
cross-device correction that merges the transcript places each turn on the
recording. A turn can be highlighted or sought only when the recording actually
covers it: only when every one of that speaker's own recordings went into the
merge. A merge missing a stretch would otherwise seek to the wrong second and
show the wrong words lit — so a turn whose coverage is uncertain stays readable
but is not made playable.

While the full call plays, the turn being spoken is highlighted and scrolled to,
and a tap on any turn's time plays from there. Hearing which words are being
said while reading them is the one thing the recording adds over the transcript;
it is the reason to keep the transcript and the recording on one screen rather
than two. The follow-along yields to the reader — scrolling by hand suspends it
until playback moves on — because a screen that fights the reader's own scroll to
chase the playhead is worse than one that simply plays.

The full recording is assembled from both halves and a merge, none of which need
have arrived when the screen opens. So the bar shows its own waiting state — not
an error — until either the merge arrives or a short grace elapses; only after
the grace does it say there is no full recording. Announcing "no recording" the
instant the screen opens, before the other side's half has had time to upload,
calls a healthy call broken. The grace is measured monotonically, for the same
reason the capture clock is: a wall-clock correction must not lengthen or shorten
the wait.

---

## Notes for review

- **Length/voice:** kept to the doc's register (design + why, present tense, no
  code identifiers, no impl detail). ~1 screen, matching the sibling subsections.
- **No new claim about analytics or retention** — playback changes neither; those
  remain the org doc's.
- **Open wording choice:** "full call" vs "whole call" vs "the recording" — the
  UI label is "Full call"; the doc uses "full call"/"merged recording". Align to
  whichever the owner prefers as the canonical term.
- **Depends on shipped behaviour:** finalize the "yields to the reader" and
  "only when every recording went into the merge" sentences against what agent 5
  actually ships (the seek-into-shared-player path was flagged as possibly
  awkward in the build brief). Re-confirm before the doc edit lands.
- **l10n:** the one new UI string this PR adds ("Play from {time}") is a separate,
  known l10n_sync_check item deferred to Gabby; not a doc concern.
