---
applyTo: "lib/routes/chat/calls/speech_trim.dart,lib/routes/chat/calls/call_transcript_sink.dart"
---

# Trimming a call chunk to the part somebody spoke

## The defect

A device captures its own outbound audio for the whole call, so while the other
person talks it records its own noise floor. One real 40.4s chunk was ~22s of
scattered non-speech followed by ~18s of speech.

Measured, on that recording:

| audio sent | Deepgram | local Whisper (base, en) |
|---|---|---|
| whole 40.4s | 3 words | `Hey.` for 0-22.04s, then the speech |
| 22.3-40.2s only | 47 words, correct | clean, and recovers a whole clause the full run lost |
| 0-10s / 10.2-13.6s / 13.6-18.0s / 18.0-22.0s | 0 words (10.2-13.6) | empty, every one |
| 15.9-17.9s | 4 words, repeated hallucination | - |

Two providers fail the same way, so this is not a provider defect. The
whole-file `Hey.` is fabricated: every sub-span of 0-22s transcribes to nothing.
**Today, non-speech does not merely waste a request — it invents words and
credits them to the learner.** That is the baseline any change here is measured
against, and it is why an honest "captured, held nothing" is an improvement on
the current behaviour rather than a new risk.

## What was measured before choosing

All measurements are on the one 40.4s recording. Local Whisper made the loop
free, so policies were compared by transcribing their actual output rather than
by argument.

**Level cannot separate the regions.** 20ms-window RMS: p10 = 36.7, speech
median 1356, but the non-speech region reaches 1965 — *above* the speech median.
A fixed floor at 1000 and an adaptive floor at 8x the noise estimate both fail,
each keeping 76-88% of the file.

**Splicing out interior gaps makes the transcript worse.** Excising and
concatenating retained spans (32.8s in 7 pieces) produced looping output —
"turn-by-turn transcripts" twice — worse than sending the whole file. Splice
discontinuities are their own damage. **This rules out the excise design, and
with it any fan-out.**

**Voicing periodicity separates the regions.** Normalised autocorrelation peak
over a 70-400 Hz lag band, per 32ms frame:

| statistic | 0-22s (non-speech) | 22-40s (speech) |
|---|---|---|
| voiced-frame fraction, per second | 0.00 - 0.30 | 0.40 - 0.94 |
| longest contiguous voiced run @ peak>=0.70 | 140-180 ms | 660 ms |
| runs >= 200ms | 0 | 20+ |

## The design

**One request per chunk, on a contiguous trim.** Find the region of the chunk
holding speech, take the single contiguous span from its first to its last
moment, and send that. Never split a chunk across requests; never splice.

### Why contiguous, not fan-out

This dissolves rather than solves the identity, cost and mapping problems:

- **Identity.** One chunk still produces exactly one request, so `chunk.index`
  remains the whole key. `_running`, `_transcribed`, `_byIndex` and `_placements`
  are untouched. No new keying scheme exists to get wrong.
- **Request cost.** Never more requests than today and strictly fewer bytes.
  Timeouts, retries, rate limits and partial-failure states are unchanged
  because the request *count* is unchanged.
- **Position mapping.** The span is contiguous, so provider timings are the
  original timeline shifted by one constant.

### The safety property this design is built on

The classifier is calibrated on one recording, so it *will* be wrong. The two
directions of error are **not** symmetric, and the design is arranged around that:
**a false positive sends more audio and is self-correcting; a false negative
drops speech and is only bounded by the guardrails below.**

| error | effect | bounded by |
|---|---|---|
| false voicing with no real speech elsewhere | span widens | nothing needed — at worst today's behaviour |
| false voicing that PINS the span away from real speech | span lands on the wrong sound | rule 4 |
| false silence on part of a chunk | span narrows | rules 2, 4 |
| false silence on a whole chunk | chunk skipped | rules 1, 3, 4 |

The second row was missed in an earlier draft, which claimed false voicing was
always safe. It is not: a fan or a hum periodic enough to pass for speech pins a
span around *itself*, and aperiodic speech elsewhere in the chunk then falls
outside that span and is cut away. Rule 4 closes it, by asking about the audio
being LEFT OUT rather than only about chunks with nothing to keep.

Four rules bound the unsafe direction. They are the reason a one-recording
classifier is allowed to make this decision at all:

1. **A short chunk is never trimmed and never skipped.** Below
   `minTrimmable` (8s) the chunk is sent whole, untouched. The defect requires a
   lot of non-speech to swamp a little speech; a short chunk cannot be swamped,
   and this is where a one-word answer lives.
2. **A trim that is not a clear win is not taken.** If the span covers more than
   `keepWholeAbove` (70%) of the chunk, the whole chunk is sent. Marginal trims
   buy little and carry all of the clipping risk, so they are refused.
3. **Skipping requires a long chunk with no speech frame anywhere in it.**
4. **Sound we cannot explain, ANYWHERE outside what we were going to send,
   means sending the whole chunk.** Audio with no periodicity but sustained
   energy is audio we do not understand, not audio we know to be empty —
   whispered and wholly unvoiced speech look exactly like this. The measure is
   the **loudest `loudWindow` (3s) stretch** lying outside the chosen span,
   scored as the fraction of its 20ms windows above 4x the chunk's own
   10th-percentile level. At or above `skipBelowLoud` (0.85) the whole chunk
   goes. A chunk with no span at all is the same question with nothing kept, so
   this is one rule rather than a special case for suppression — which is also
   what closes the false-voicing hole above.

   A range shorter than `loudWindow` scores zero: a stretch too short to fill
   the window is not the sustained sound this looks for, and scoring it over
   whatever it did cover would let a single burst beside the span veto every
   trim.

   The bar is relative to the chunk's own floor, which assumes the chunk HAS a
   quiet part. `quietFloor` is the backstop for when it does not: a chunk whose
   own 10th percentile already sits above -45 dBFS is loud everywhere, the
   relative test measures nothing, and it is never suppressed. This uses level,
   but only ever to *refuse* to skip or trim, which is the safe direction.

   The loudest stretch rather than the chunk average, because an average cannot
   tell continuous sound from scattered bumps. Averaged, a chunk of 22s noise
   plus 18s of *whispered* speech scores 0.58 against pure noise's 0.46 —
   eighteen seconds of somebody talking separated from room tone by twelve
   points, and on the wrong side of any threshold that still suppressed the
   noise. Over the loudest three seconds the same cases score 0.99 and 0.72,
   against 0.39-0.72 for non-speech and 0.97-0.99 for speech throughout.

Applied to the recording: the 40.4s chunk trims to 46% and is trimmed; the
17.9s pure-speech span measures 100% and is sent **whole**; a 3.4s noise chunk is
sent whole for being short; 10s and 22s pure-noise chunks are marked silent; and
a 350ms utterance buried in 8s of this recording's own noise is found and
trimmed to.

### Deciding what is speech

Per 32ms frame at 20ms hop, on the signal reduced to ~4 kHz:

1. **Decode.** PCM16 little-endian. Every offset is computed in whole sample frames
   (`bytesPerFrame = 2 * channels`), so a slice can never land mid-sample or
   mid-frame and shift the channel phase.
2. **Take the loudest channel, never the average of them.** Averaging is the
   obvious downmix and it is not safe: two channels in opposite phase sum to
   nothing, so a signed mean would hand the voicing test digital silence for a
   chunk somebody is talking through. One channel taken whole cannot cancel and
   keeps the waveform the autocorrelation needs. The level veto is separate and
   sums energy ACROSS channels, for the same reason.
3. **Decimate** by the integer factor `sampleRate ~/ 4000` (4 at 16 kHz, 12 at
   48 kHz), each output sample being the mean of the factor's worth of input
   samples — a box filter, which is a real if crude anti-alias lowpass rather
   than bare subsampling. Pitch lives below 400 Hz, so the retained band is
   ample. All lag bounds are recomputed from the ACTUAL decimated rate, so a
   rate that does not divide evenly is still handled correctly.
4. **Voiced** if the normalised autocorrelation peak over the lag band
   corresponding to 70-400 Hz is `>= voicedPeak` (0.70).
5. A frame is **speech** if either
   - **sustained**: the voiced fraction over a `smoothWindow` (2000ms) window
     containing it is `>= speechFraction` (0.45); or
   - **isolated utterance**: it lies in a contiguous voiced run of at least
     `minVoicedRun` (200ms).
6. The span runs from the first speech frame to the last, padded by `pad`
   (300ms) each side and clamped to the chunk.
7. No speech frame at all, in a chunk at or above `minTrimmable`: **captured but
   silent**. Not sent.

There is deliberately **no minimum span length**. Criterion (5b) is what keeps
short answers — "haan", "nahi", "yes", "okay" are the credit-bearing utterances
a learner produces. Contiguous trimming also retains any short word falling
between the first and last speech, whole.

**No energy pre-gate.** An earlier draft skipped frames below 2x the chunk's own
10th-percentile energy. It saved 31% of the work and changed the answer by 0ms,
but it is a *level* test in front of a design whose premise is that level does
not separate speech from non-speech: a raised floor (fan, echo, a room) could
delete quiet real speech before the voicing test ever saw it. It was removed
rather than tuned. Cost without it is ~0.5s in prototype Python for 40.4s of
audio, so a fraction of that in Dart — the optimisation was never needed.

### What the trim hands to the sink

One value carrying all three parts together, so no caller can shift the audio
without shifting its position:

```
TrimmedChunkAudio { Uint8List wav; int startMs; int durationMs; }
```

`startMs` is the offset into the chunk; `durationMs` is the length of the audio
actually in `wav`. `PcmChunk.toWav()` is unchanged and still wraps the full PCM —
the trim builds its own WAV from a sample-frame-aligned view. The sink then
records

```
_placements[index] = (startedAtMs: chunk.startedAtMs + startMs, durationMs: durationMs)
```

and sends `wav`. Because the audio is contiguous, the existing linear
`_positionOf` is exactly correct, and `_isWellFormedSequence` bounds timings
against the audio actually sent rather than against audio that was not. No
piecewise map exists.

### Accounting

`chunksCaptured` is today `_transcribed.length + _failed.length`, both mutated
inside `deliver()`, so a chunk never delivered vanishes from the denominator —
the opposite of what that accounting is for. Silence gets its own state:

- `_suppressed` — captured, judged to hold no speech *by this device*, no
  request issued.
- `chunksCaptured = _transcribed.length + _failed.length + _suppressed.length`.
- `chunksLost` stays `_failed.length`.

**A locally suppressed chunk is not the same fact as a chunk the provider read as
silence, and it is not written as one.** The provider's silence is a judgement by
the thing that actually reads speech; ours is a judgement by a detector
calibrated on one recording, and the difference is exactly the risk this design
carries. So it becomes a first-class count on the wire, `chunks_suppressed`, and
a reader can see how much audio a device decided not to send.

It is deliberately **not** folded into `writerAdmitsGaps`. Almost every real call
has a quiet stretch, so a flag raised by ordinary silence would mark nearly every
transcript incomplete — which is precisely the reasoning already recorded on
`chunksLost`, and it would leave the flag meaning nothing when it matters. The
count is there to be *read*, not to cry wolf.

The reader's coherence invariant widens with it, to
`transcribed + lost + suppressed <= captured`, and every rule that enumerates
counts must name it — the codebase has already made the
enumerate-some-of-the-counts mistake twice, and `refusedYetRecorded` is the rule
that has to learn about this one.

`deliver()` checks `_running`, then `_suppressed`, then `_transcribed`, so a
redelivered suppressed chunk is neither re-analysed nor double-counted.

### Not touched

`PcmChunker` keeps its no-sample-lost invariant unchanged. Cutting for *size* and
trimming for *transmission* are different questions: the chunker still emits
every sample it was given, and the trim happens downstream at the request.

## Numbers, and which are not validated

Calibrated against ONE recording. All are named, injectable constants, so a
second sample retunes without rearchitecting.

| constant | value | basis |
|---|---|---|
| `voicedPeak` | 0.70 | measured plateau: at 0.65 noise runs cap at 180ms, at 0.75 at 140ms; speech keeps 20+ runs >=200ms either way. Mid-plateau. |
| `minVoicedRun` | 200ms | above the 140-180ms noise ceiling at this peak, below the voicing in the shortest real words. **Thinnest margin in the design.** |
| `speechFraction` | 0.45 | mid-plateau; insensitive (below) |
| `smoothWindow` | 2000ms | mid-plateau; insensitive (below) |
| `pad` | 300ms | **unvalidated.** Chosen to cover unvoiced onsets and codas, not measured. |
| `minTrimmable` | 8000ms | **unvalidated.** A judgement about how much non-speech it takes to swamp speech, not a measurement. |
| `keepWholeAbove` | 0.70 | **unvalidated.** A judgement about when a trim stops being worth its risk. |
| `skipBelowLoud` | 0.85 | measured over the loudest 3s: non-speech scores 0.39-0.72, speech and unvoiced surrogates 0.97-0.99. Mid-gap. |
| `loudWindow` | 3000ms | **unvalidated.** Long enough that scattered bumps cannot fill it. |
| `quietFloor` | 0.0056 (-45 dBFS) | **unvalidated from below.** Above the reference recording's -59 dBFS room noise; no steady whispered sample exists to place it against. |
| `loudMultiple` | 4x own p10 | **unvalidated.** The level that counts as "not the floor". |
| 4 kHz / 32ms / 20ms | - | standard pitch-tracking geometry, not tuned here |

`speechFraction` and `smoothWindow` are **not sensitive**: at `voicedPeak` 0.70 a
5x8 sweep (smooth 1000-3000ms x fraction 0.25-0.60) put every one of the 40 cells
in 20.3-22.0s start and 39.2-40.4s end. Raising the voicing threshold is what
made them nearly irrelevant, which is why the design leans on periodicity rather
than on the smoothing.

Five of the twelve numbers are judgements rather than measurements. Four of them —
`minTrimmable`, `keepWholeAbove`, `loudMultiple`, `quietFloor` — fail toward
**sending more audio**: each is a threshold for *declining* to trim or skip, so being wrong about
it costs a request, not a word.

`pad` is the exception and should not be listed with them. It is the one
boundary number whose error deletes speech: too small and an unvoiced onset or
coda past 300ms is clipped off the front or back of a trimmed span. It does not
fail safe, it is simply bounded — see Known gaps.

## Result on the recording

Span 21.96-40.38s: 18.4s of 40.4s, 46% sent. Whisper on that audio returns three
segments, all real content, with no fabricated `Hey.` and no repetition.

## Known gaps

- A chunk at or above `minTrimmable` whose only content is a sub-second
  utterance in long noise may be marked silent. Not a regression: measured, the
  providers return nothing (Deepgram, 0 words) or hallucination (4 repeated
  words) for exactly that audio today, so this trades fabricated credit for an
  honest "held nothing" — the better error in an app that credits vocabulary.
  But it IS a decision made on one recording's calibration. It does not raise
  `chunksLost` — it is not a failure — so it is published as `chunks_suppressed`
  instead, and a reader that wants to distrust this device's judgement has the
  number to do it with.
- Normalised autocorrelation is invariant to **gain**, not to additive noise,
  clipping, echo, periodic hum or codec artifacts. The claim it supports is only
  that the decision needs no per-device *level* calibration; it is not a claim of
  robustness to interference. Periodic interference produces false voicing, which
  is the safe direction.
- Calibrated on one recording, one speaker, one room, one device.
- The end-to-end gain is validated on Whisper and *inferred* for Deepgram from
  the brief's measurements. It was not re-measured against Deepgram, which is
  billed.
- **A short WHOLLY UNVOICED answer in a long quiet chunk is suppressed.** Rule 4
  protects a chunk carrying a sustained stretch of aperiodic sound, including
  one where noise outweighs the speech. It does not protect 350ms of whisper in
  eight seconds of quiet: no three-second stretch of that chunk is loud.
  The obvious repair — veto suppression on a RUN of loud windows anywhere in the
  chunk, rather than a sustained stretch — was measured and refused. The reference recording's
  non-speech stretch contains **thirteen loud runs of 200ms or more, the longest
  960ms**: longer and louder than the whispered answer the rule would exist to
  protect. It would therefore refuse to suppress the exact audio this design
  exists to stop sending, which transcribes to nothing on both providers and to
  invented words on each.
  Energy cannot separate the two cases. Separating them needs spectral
  structure, and there is no whispered sample here to calibrate it against.
  The behaviour is pinned by a test so it stays visible.
- **Boundary clipping is bounded, not eliminated.** This is an accepted
  limitation, not a solved problem, and it is inherent to cutting on voicing.
  The exposure is narrow on three sides at once: it applies only at the edges of
  a span that was actually *trimmed* (rule 2 sends anything above 70% speech
  whole), only to unvoiced material running more than `pad` = 300ms beyond the
  nearest voiced frame, and only to the head and tail of a chunk rather than
  anywhere inside it. Typical aspirated onsets and sentence-initial fricatives
  run 50-200ms and fit inside the pad; something longer would not.
  What can be said from evidence: on the one real trim available, Whisper
  returned *more* correct content from the trimmed audio than from the whole
  file, so nothing was clipped there. What cannot: no whispered or
  heavily-aspirated sample exists here, so the pad's sufficiency is asserted from
  phonetics rather than measured. A wholly whispered chunk is separately
  protected by rule 4, verified against a synthetic surrogate only.
- Voiced-run length cannot separate a short real utterance from a noise burst at
  `voicedPeak` 0.55, where noise reaches 260ms. The design depends on the higher
  threshold to open that gap.
