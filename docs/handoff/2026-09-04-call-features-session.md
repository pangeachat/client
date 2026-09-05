# Call features session — 2026-09-04

Three call features being integrated and tested on the LAN before PRs. All
local, nothing pushed.

## Branches / commits (client repo)
- `satvik/tokenize-call-transcript` — #8797 (tap a transcript word to open its
  word card) `4b3ced372f`, cold-green + mutation-proven; #8807 v1 (single
  ringback) `0bdfeb93c4`; **#8807 3-cue `1925844ca5`** — three standard
  telephony cues (ringback placing / call.ogg reconnecting / end tone on cut),
  owner heard and approved the sounds locally. Tests: transcript_tokens (5),
  ring_player (generation-token race), call_session (rewritten ringback group).
  The 3-cue commit is NOT cold-gated yet — owner approval was on the SOUND;
  the cold gate is the pre-push bar, run it before the #8807 PR.
- `satvik/call-audio-recording` — each device saves its own call audio to the
  room at the finish seam (`pangea.call_audio`, plain mxc url since rooms are
  unencrypted, write gated on `carriedOn`); offline merge tool
  `tools/merge_call_audio/`. The phone APK was built from here (recording-only:
  no #8797/#8807).
- `satvik/call-features-combined` — merge of the two above, TEST INTEGRATION
  ONLY (not a PR). Base merge `d7f3ff642a`, then the 3-cue merged in clean.
  Both features coexist (recording + 3-cue markers both present), calls surface
  analyzes clean.

## Served for testing NOW
- Combined web build #2 (all 3 features, tones bundled, LAN `.env`) served at
  **http://192.168.1.156:8091** from `combined/build/web` (python http.server,
  bg task `bnexnpkj5`). Rebuilt clean (`rm -rf build/web` first) so no stale
  bundle in the artefact — but the BROWSER can still serve a cached SW bundle,
  so the tester must hard-refresh / use a fresh window.
- LAN call path fully green: advertised focus `http://192.168.1.156:7980`,
  lk-jwt `LIVEKIT_URL=ws://192.168.1.156:7880`, SFU :7880 -> 200, Synapse :8008
  -> 200, lk-jwt :7980/healthz -> 200. Accounts @learner and @rectest /
  learnerpass both log in (200).
- Test shape: laptop (:8091, all 3 features) is the CALLER so it hears the 3
  cues; phone (recording APK) answers and records its half. Word-cards are
  viewable on the laptop transcript. The recordings player is NOT in this build.

## Done since (2026-09-04, live test round)
- **Word-card bug fixed** `c6460b66d9` on `satvik/tokenize-call-transcript`.
  Symptom (owner saw it on the LAN test): the card opened from a call
  transcript had a DOUBLE border and a clipped definition, unlike the normal
  message card. Root cause: `PositionedOverlayDisplayDetails.addBorder`
  defaults to `true`, so `showPositionedCard` wraps the card in a bordered
  `OverlayContainer` (overlay_container.dart draws `Border.all` + radius 25) —
  but `WordZoomWidget` already draws its OWN border (word_zoom_widget.dart:173)
  and OverlayContainer's constraints crop its fixed height. The RULE: a
  `WordZoomWidget` shown via `showPositionedCard` must set `addBorder: false`
  (the widget owns its border). The only other such site (activity_vocab
  widget) already does; #8797 was the one that didn't. Fix also turns on
  `enableEmojiSelection` + `enableAnalyticsNavigation` (the default card carries
  them; both need no event) — reactions + report-flag stay off (a transcript
  has no room message event). analyze clean, 5 transcript_tokens tests green.
  NOT visually re-verified in-session (needs a live call) — owner verifies on
  the rebuild.
- **Recordings player merged.** Agent `aa4e66aebd4a7ed9d` finished:
  `24203fd711` on `satvik/call-audio-recording` — `call_audio_repo.dart`
  (`fetchCallAudio`, mirrors `fetchCallTranscript`'s relations walk on the same
  `callKey`) + a "Recordings" section below the transcript in
  `CallTranscriptView`, one `AudioPlayerWidget` per `pangea.call_audio` event.
  Reuse detail: the raw event type isn't `m.room.message`, so
  `downloadAndDecryptAttachment` would throw; the agent feeds a SYNTHETIC
  `m.audio` message event carrying the same plain mxc url to the unmodified
  player. Mutation-proven tests (both directions), 1410 calls tests green.
  NOT cold-gated yet — gate before the recording PR.
- Both merged into combined clean (no conflicts): card fix + player + 3-cue.
  gen-l10n run for the new `callTranscriptRecordings` key; calls analyze clean.
  Combined build #3 building (bg `b8766xeif`) -> re-serve on :8091.

## Next
1. Build #3 lands -> re-serve :8091 -> owner re-tests the word card (single
   border, uncropped) and the recordings player on the live call.
2. Cold-gate, before the PRs (pre-push bar): the 3-cue `1925844ca5` + card fix
   `c6460b66d9` (#8797/#8807 branch), and the recordings player `24203fd711`
   (recording branch). None gated yet.
3. #8808 (transcript loading state) still queued — needs the "still processing"
   signal decision (current lean: listen + settle, not a spinner-forever).
4. PRs #8797 + #8807 await owner PR-go; batch-merge with the recording work as
   one deploy on owner go.

## 2026-09-04 (II) — RECORDING IS BROKEN ON WEB (owner found it live)

Owner tested a real call with TWO WEB endpoints (incognito @learner + normal
@calltester) and saw NO recordings. Investigated and REPRODUCED: a full web call
on the combined build (:8091) via the E2E harness (`test/e2e/transcript.js`, two
headless Chrome) writes the transcript but **0 `pangea.call_audio` events** (room
`!Hgav`, 19:11:39). Confirmed directly against the rooms (every room audio=0).
- The recordings PLAYER is CORRECT — it renders nothing because nothing was
  recorded. Not a player bug, and NOT a stale/wrong build (both the owner's test
  and the harness ran the right build).
- Write path: the audio tap is chosen by `defaultCallAudioTap`
  (call_audio_tap.dart:~418) — `PostEchoCancellationTap` only on Android,
  `TrackRendererTap` on web + iOS. On web the recorder emits no `call_audio`.
- **Why the earlier "green" missed it (owner asked):** the player agent's tests
  use SYNTHETIC `call_audio` events (prove display, never the write). The
  recording feature's unit tests INJECT a fake tap + frames (prove the recorder's
  logic GIVEN frames, never real platform capture). Neither ever ran a real
  browser call. It's a coverage gap at the platform-integration seam, not a
  rigged test. The fix must therefore ALSO add a real E2E gate: a web call must
  assert a `call_audio` event actually lands.
- Owner requirement: recording must work on **web, iOS, AND Android**.

Root-cause workflow launched (ultracode): script
`scratchpad/diagnose_recording.mjs`, run `wf_1543f2e3-a0e`, task `wubv8zcph`.
Four parallel diagnoses (live browser-console capture via a patched harness /
real livekit_client web source in the pub cache / capture-vs-recorder wiring /
publish gate + iOS) -> synthesis -> three adversarial verify lenses. Returns the
confirmed root cause + the cross-platform fix + the REAL gate.

HOLD: do NOT open the recording PR until web/iOS recording works and the real
gate is in. Card fix `c6460b66d9`, 3-cue `1925844ca5`, player `24203fd711` all
still local; the #8797/#8807 PRs can proceed independently once cold-gated.

## 2026-09-04 (III) — ROOT CAUSE FOUND + FIXED (web recording) + real gate

Diagnosis workflow `wf_1543f2e3-a0e` (SURVIVED 3/3 adversarial lenses, 0 refuted)
found it, CONSOLE-PROVEN:

ROOT CAUSE: `CallAudioRecorder._newGenerationId()` minted its id with
`_idRandom.nextInt(1 << 32)`. On web (dart2js) `1 << 32` overflows to 0, so
`Random.nextInt(0)` throws a RangeError synchronously inside `onRunStarted` -- on
the first audio frame, before any generation is created -- killing the recorder.
The transcript mints no id and was undisturbed, which hid it. Verbatim in the
captured browser console. Android/iOS run native 64-bit ints (`1<<32 == 2^32`, a
valid bound) so they are unaffected; iOS unverified on-device (safe from THIS
bug, but confirm separately).

WHY GREEN MISSED IT (owner's question): unit tests run on the Dart VM (64-bit
ints, no overflow) and inject frames/generations directly; the player tests feed
synthetic `call_audio` events; the transcript E2E asserts only the transcript
half and the recorder's throw is deliberately swallowed. Nothing ran the
COMPILED dart2js client through a real call asserting a `call_audio` event lands.

FIX (call_audio_recorder.dart + call_capture.dart):
1. `nextInt(1 << 32)` -> `nextInt(0x40000000)` (2^30, dart2js-safe, ample beside
   the microsecond timestamp).
2. Defense-in-depth: latch `_audioRunFormat` only AFTER onRunStarted succeeds, so
   a run-open throw retries on the next frame instead of permanently killing the
   recorder after one swallowed warning (`_runStartFailed` logs once per streak).

REAL GATE (test/e2e/transcript.js + harness.js): a `[4b]` assertion that a
`pangea.call_audio` event with an mxc blob lands after a real web call (runs the
COMPILED build, so it exercises dart2js semantics a VM test cannot), plus a
recorder-failure console gate that turns the swallowed 'failed to start a run'
warning RED.

VERIFIED: fixed web build, 2-Chrome harness call -> 17/17, `call_audio` written +
uploaded, no recorder failures. Mutation proof (revert id -> rebuild -> watch
`[4b]` FAIL) IN PROGRESS to confirm the gate catches the exact bug. Then:
cold-gate the code change, restore + rebuild the fixed build on :8091, and the
recording work is ready for its PR (pending the iOS on-device confirmation).

## 2026-09-04 (IV) — fix cold-gate GREEN + honest gate reach

Codex cold-gate on the fix `b1b85ed725`: GREEN, 0 real issues (0x40000000 bound
correct; the retry-ordering safe -- no loop/spam, invariants intact; the E2E gate
honest). Verdict `/tmp/recfix-gate-verdict.txt`. Mutation proof already done:
reverting only the id makes exactly the 4 recording checks fail (RangeError
console-proven) and the harness exit 1, transcript checks still pass.

HONESTY on the gate's reach (Codex flagged it, confirmed): the E2E `call_audio`
assertion CATCHES the bug but runs `client/test/e2e/transcript.js` against a LOCAL
STACK (Synapse/lk-jwt/LiveKit/choreo + 2 Chrome) -- it is a manual/pre-push gate,
the same way the whole call feature is tested (pangea-call-testing skill). It is
NOT in the default unit CI: `integrate.yaml` `code_test_shards` runs `flutter
test` on the VM, and there is NO `--platform chrome`/web-compiled lane anywhere in
`.github/workflows`; CI's `e2e-tests.yml` runs a DIFFERENT Playwright suite
(`e2e/scripts/*.spec.ts`), not this puppeteer harness. A VM unit test CANNOT catch
this class (the VM computes `1<<32` correctly). A fully-automated CI gate would
need a new chrome-platform test job -- an owner-gated CI change, PROPOSED not
added.

State: fix committed on combined `b1b85ed725`, fixed build on :8091. NOT yet
ported to `satvik/call-audio-recording` (the PR branch). iOS on-device recording
still unverified (safe from this bug). Open owner decisions: (a) add the
chrome-platform CI lane for an always-on gate; (b) port + open the recording PR;
(c) iOS device check.

## 2026-09-04 (V) — remaining-work audit + two more same-class bugs fixed

Ran the remaining-work audit workflow (`wf_de134f2c-a3b`). It found TWO more
platform bugs of the SAME unit-green/platform-broken class as the recording one,
both now fixed:

1. PORT DONE. The web-recording overflow fix was ONLY on the combined branch; the
   recording PR branch `satvik/call-audio-recording` tip (`24203fd711`) still had
   `1<<32`. Cherry-picked `b1b85ed725` -> now `6df82df214` on
   `satvik/call-audio-recording` (identical diff, so the cold-gate verdict
   carries). Verified `0x40000000` present. The dirty pubspec `.env`-asset line
   was stashed (local build artifact, not committed).

2. OGG-ON-iOS FIXED. The three RingPlayer cues (incoming ring `phone.ogg`, busy
   `notification.ogg`, reconnecting `call.ogg`) were OGG, which audioplayers
   cannot decode on iOS/macOS -> silent ring, missed calls; `ringback.mp3` /
   `call_ended.mp3` already played (a half-migration). Converted to
   `phone.mp3`/`notification.mp3`/`call.mp3` and repointed the three cues; left
   `phone.ogg` (base VoIP ringtone) and `notification.ogg` (web notification,
   browser-decoded) untouched. Commit `26a67d96c4` on
   `satvik/tokenize-call-transcript`. analyze + 63 ring/call tests green; MP3
   plays everywhere. iOS on-device confirmation still owed.

Remaining (from the audit, prioritized):
- MUST before ship: iOS on-device recording + cue verification (needs a device);
  web compiled-build E2E recording + playback confirmation; recordings-player
  on-device playback + the web large-WAV base64->Blob playback fix.
- In-flight: cold-gate `c6460b66d9` (#8797 card fix), `1925844ca5` (#8807 sounds),
  `24203fd711` (player), and the OGG fix `26a67d96c4`.
- Owner-gated: #8797-vs-#8807 PR split, opening/batch-merging the PRs, the
  compiled-web CI lane, the #8808 settle-signal design.

## 2026-09-04 (VI) — cold-gate of the 4 ungated commits: 1 GREEN, 3 RED -> fixed

Gate workflow `wf_f11a5202-a49`: `c6460b66d9` (#8797 card fix) GREEN; the other
three RED, all now fixed:
- #8807 `1925844ca5` **HIGH**: the cut cue had no placedCall guard, so the
  ANSWERER played call_ended.mp3 on every answered-then-ended call (both devices
  run _onCallChanged). FIXED `66ffac7d36`: guard the cut block on
  `call.placedCall` (caller-only, matching the doc + pre-#8807 behaviour). Tests:
  answerer-no-cut, tightened cut order to the exact [stop, once:call_ended] tail,
  and a new reconnecting-cue test (drives isRecovering via a
  `_FakeRoster.setRecovering` seam; also locks `call.mp3`). CUT-SCOPING is
  caller-only by DEFAULT -- owner may want BOTH parties to hear the end tone
  (flagged for confirmation).
- recordings player `24203fd711` **MEDIUM** (code was GREEN): the test never
  asserted the synthetic event is PLAYABLE. FIXED `7330862c15`: assert
  type/msgtype/mxc-url/info.size on each player's event.
- OGG `26a67d96c4` **LOW x3**: no test locks the .mp3 cues. Reconnect cue now
  locked (the reconnecting test). Incoming-ring (phone.mp3) + busy
  (notification.mp3) locks DEFERRED -- low value, and the busy asset is only
  assertable at the audioplayers channel level the ring tests deliberately mock;
  the code comment at each cue ref guards against a revert.

Working: 17/17 E2E on combined; 55 call_session + 58 player unit tests green.
Re-gate of `66ffac7d36` + `7330862c15` running (codex). Branch tips (all local):
`satvik/tokenize-call-transcript` = `66ffac7d36`; `satvik/call-audio-recording`
= `7330862c15`.
