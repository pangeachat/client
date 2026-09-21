# Recording-based call transcript v2 — design spec

Status: DRAFT for cold-gate + owner sign-off (2026-09-21). Supersedes the v1 client-only
attempt (flag-gated dark on satvik/call-features-combined; failed on the 10MB cap for long
calls and on post-hangup app backgrounding dropping the phone's half).

## Goal

Each speaker's call transcript is generated from that speaker's OWN continuous call recording
(the same audio the merged playback / "mix" is built from), not from live 45-second chunks.
Works reliably for ANY call duration up to ~1 hour, and never silently loses a half.

## Why recording-based is better ordered (the mix insight)

The mix is natural because it is each device's CONTINUOUS recording, time-aligned on one clock.
The live path is unnatural because it chops each side into 45s chunks in real time, transcribes
each in isolation (word timings reset per chunk, sentences split at chunk boundaries, chunks
drop on mute/unmute, and `_alignedToTranscript` mis-orders when STT tokenization diverges).
Transcribing each WHOLE recording in one logical pass gives word timings that flow across the
entire call, cut at natural pauses, placed on the same device clock the reader already corrects
per half -- so it interleaves with the other speaker exactly like the mix does.

## Architecture

Two producers of the SAME transcript half, deduplicated by the deterministic transaction id
(call_key + sender + device) that already keys the half -- Synapse collapses duplicates, so
whichever lands first wins and a second identical post is a no-op:

1. CLIENT path (fast, robust). At hangup each device already uploads its recording (the
   `pangea.call_audio` half). It additionally: transcribes its OWN recording via choreo,
   CHUNKED so any length stays under choreo's 10MB base64 STT cap; assembles the segments with
   the existing `buildRecordingSegments`; and posts its `pangea.call_transcript` half. Made to
   survive the app backgrounding at hangup (see Reliability).
2. SERVER backstop (choreo). Choreo transcribes the uploaded recording server-side and posts
   the same half under the same deterministic txn id. Covers the case where the client dies /
   backgrounds before its own post lands. Handles any duration server-side.

Because both use the same txn id, running both is safe and additive. The client path gives a
fast result when the app stays alive; the server path guarantees the half exists even when it
does not.

## Components

### Client (fluffychat, satvik/call-features-combined)
- ANY-DURATION CHUNKING: split the complete recording PCM into contiguous pieces each safely
  under the cap (downsampled to 16kHz mono first, as v1 already does), transcribe each piece via
  choreo `speech_to_text` with `include_word_timings`, OFFSET each piece's word timings by the
  piece's start, concatenate into one timing list, and run `buildRecordingSegments` over the
  merged list. Deterministic over the complete WAV -- no real-time drops. A piece that fails ->
  the whole client attempt yields [] and the server backstop covers it (never a partial half).
- RELIABILITY: the post-hangup transcription + publish must not be lost to app backgrounding.
  Android: keep the call's foreground service alive until finish() completes. iOS: a bounded
  background task assertion; if it cannot finish in the window, the server backstop covers it.
  Either way the SERVER backstop is the guarantee; the client is best-effort-fast.
- Keep v1's flag (`Environment.callRecordingTranscript`) gating the whole thing; default OFF
  until this is proven, so it stays revertible.

### Choreo (2-step-choreographer)
- SERVER-SIDE TRANSCRIBE + POST: given a call's uploaded recording (mxc URL from the
  `pangea.call_audio` half) + the call key + sender/device, fetch the recording from Synapse,
  transcribe it (chunk server-side or Google long_running_recognize for >1min/>10MB), build the
  same segments, and POST the `pangea.call_transcript` half under the deterministic txn id.
- OPEN QUESTION (the main design risk): HOW choreo authors a Matrix event as the speaker.
  Candidates: (a) an appservice with a user namespace; (b) the existing pangea-bot posts it;
  (c) a synapse module; (d) choreo returns the segments to the client and only the client posts
  (drops the server backstop -> weaker reliability). Resolve before building the server path.
- Do NOT weaken the 10MB cap in `speech_to_text_schema.py`; handle size by chunking/long-running.

### Reader (client)
- LIVE UPDATE: the recording-based half can arrive seconds after hangup (or later, from the
  server). The open transcript view must pick it up without a manual refresh (the v1 staleness
  bug). Prefer the recording-based half over the live one when both exist for a device.

## Build plan (each piece: RED->GREEN test + cold-gate before the next)

P1. Client any-duration chunking + merge (foundation; unblocks every real call length).
P2. Client reliability (foreground-service keep-alive through finish; iOS bounded task).
P3. Reader live-update + recording-preferred-over-live.
P4. Choreo server-side transcribe (chunk/long-running) -- STT only, returns segments.
P5. Server-side POST (resolve the event-authoring model first) -- the backstop.
P6. E2E on real devices, any-duration, mute/unmute, app-backgrounded.

P1-P3 make the CLIENT path robust (covers most real calls). P4-P5 add the server guarantee.
Parallelizable: client (P1-P3) and choreo (P4-P5) are separate repos/streams.

## Constraints (standing)
- No gate rigging; fix code not gates. Cold-gate every piece to GREEN; on RED root-cause.
- No choreo server-config / worker / limit change without owner approval + a 1-liner.
- Flag-gated + revertible throughout; default OFF until E2E-proven.
- No emojis in code/commits; PRs only on explicit owner go.
