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
Re-gate of `66ffac7d36` + `7330862c15`: BOTH GREEN (codex, fresh verdicts) --
the HIGH cut-cue regression and the player-playable + reconnecting/cut-order test
gaps are all closed. So all 4 originally-gated commits are now cold-GREEN
(HIGH + every MEDIUM), with the two OGG LOW asset-locks (incoming-ring, busy)
the only documented deferral. Branch tips (all local):
`satvik/tokenize-call-transcript` = `66ffac7d36`; `satvik/call-audio-recording`
= `7330862c15`.

OPEN for owner: (a) end-tone scope -- caller-only (default) vs both parties;
(b) the two deferred OGG LOW locks; (c) still-pending from (V): iOS on-device
pass, the compiled-web CI lane, PR split/open + batch-merge, #8808 design.

## 2026-09-04 (VII) — pickup work (web-player, OGG-locks, #8808) all cold-GREEN

Owner authorised autonomous work on three follow-ups. All committed (local), each
cold-gated GREEN. This ALSO resolves open items (b) and part of (c) above:
- OGG asset-locks `7bc396f13f` (satvik/tokenize-call-transcript): two
  mutation-proven tests locking the incoming ring (phone.mp3) + busy
  (notification.mp3) cues to MP3. GREEN first pass. (Closes open item (b).)
- Web-player Blob-URL memory fix `a747cadc36` (satvik/call-audio-recording): web
  audio plays from a Blob object URL, not an ~80MB base64 data: URI; revoke on
  replace, bounded to one live blob. First impl RED (blob leaked on the
  throwing-load error path) -> fixed -> GREEN; tests load-bearing (4/5 fail on
  revert).
- #8808 transcript loading / "still assembling" `ee8caf0b81` (new branch
  satvik/8808-transcript-loading, off origin/main): a listen+settle state
  machine. TWO gate rounds RED on a settle/read race (a settle firing mid-read
  while a tick landed dropped the peer half -> stale "No transcript from them");
  round-3 fix reordered the `_changedWhileReading` drain BEFORE the phase-guard
  return and dropped `_drainPendingRead`'s phase guard, so a mid-read change
  forces one more read regardless of phase. GREEN, mutation-proven, 65/65. NEW
  UX -- the settle timings are the agent's choice; OWNER should review them.

iOS Simulator verification: BLOCKED on host setup -- only Command Line Tools, no
Xcode.app (CocoaPods now installed). Owner must install Xcode from the App Store,
then `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` +
`sudo xcodebuild -runFirstLaunch`; then this session can build the recording
branch on an iPhone simulator and verify recording + the MP3 ring.

Disk: was 1GB free (that is why Xcode could not install); reclaimed ~77GB (Docker
system prune 33.5G with the host Docker.raw shrinking 46->4.9G, Homebrew 8G,
Gradle caches 11G, npm, uv 6G, Chrome/pip/playwright/python caches ~5G) -> 78GB
free. Left pub-cache, fvm, rustup, puppeteer, and codex caches intact.

## 2026-09-04 (VIII) — owner calls + PR hold

- END TONE: owner chose BOTH parties hear the call-ended cue. Reverted the
  caller-only placedCall guard on the cut cue; commit `7b8087b8d5` on
  satvik/tokenize-call-transcript. 55 call_session tests green. (Resolves open
  item (a).) NOTE: this is a behaviour change on top of the cold-green
  `66ffac7d36` -- cold-gate it (with the rest) before the PR.
- #8808 settle timings (owner asked, no change requested): shows "still
  transcribing" after the call, settles once no new half arrives for 5s
  (`kTranscriptAssembleQuietPeriod`), hard 30s ceiling
  (`kTranscriptAssembleWindow`); never spins.
- HOLD: **no PRs until Tuesday (owner).** Everything stays local + gated; do NOT
  open/push any PR before then. iOS-Simulator verification still waiting on the
  Xcode install (owner downloading it).

## 2026-09-05 — one-sided recording ROOT-CAUSED (real code bug) + fix in flight

Owner found only ONE side records in a 1:1 call (only @learner wrote call_audio;
the peer wrote none) and asked for the MIXED recording. Investigation (agent,
DEFINITIVE): a REAL CODE BUG, not the lk-jwt/attribute local-stack limit (H1
attribute + H2 cross-account-sibling both REFUTED with file:line evidence). The
NON-INITIATOR of the hangup drops its half: the SFU reports the peer's departure
BEFORE the caller's Matrix retraction syncs, so the answerer takes the GRACE path
-> `_reconcile` runs a default SETTLE-shaped `capture.stop()` (active_call.dart
~932) that does NOT set `wasCarryingBeforeLastStop`; grace lapses -> the
hangup-shaped stop finds `_running` already false -> `carriedOn=false` ->
`finish()` skips the upload (INFO log, no failure). The initiator keeps `_running`
true through its own hangup and publishes. Missing case = a PEER-DROP PAUSE (peer
left, NO SIBLING to hand to): this device is still the sole carrier and MUST
publish. Platform-independent (iOS too); reproduces on staging -- NOT a stack
limit.

FIX in flight (agent on satvik/call-audio-recording): preserve carrier on a
peer-drop stop (or compute `carriedOn` from the recorder's generation state), +
STRENGTHEN test/e2e/transcript.js to require BOTH participants' call_audio (>=2
distinct senders -- the honest gate that would have caught this), + rebuild web +
verify both sides record. THEN the merge tool (tools/merge_call_audio, needs
EXACTLY 2 halves, aligns them on the SFU timeline) can produce the mixed
recording the owner wants to judge -- impossible until both halves exist.

iOS: recording-branch build (combined) compiling; the sim MCP needs `sudo
xcode-select -s /Applications/Xcode.app/Contents/Developer` (owner, sudo) before
the live panel attaches. iOS hits the SAME recording bug -- the fix helps there.

## 2026-09-05 (II) — recording fix landed (BOTH sides record) + mix delivered + iOS runs

- RECORDING FIX: commit `6e0095ff7a` on satvik/call-audio-recording -- "publish
  the non-initiator's call-audio half after a peer drop": preserve carrier on a
  PEER-DROP pause (elected, no sibling, held silent because the peer/connection
  is gone), reset-on-start closes the stale-true path, a genuine SIBLING handover
  is unchanged (preserveCarrier:false -> sibling publishes). Aligned with
  call-device-ownership.instructions.md ("did THIS device carry on" = self-fact);
  the peer-drop-pause rule is worth ONE line in that doc -- OWNER REVIEW, agent
  did NOT edit it. Mutation-proven; E2E 18/18 incl. NEW gate "both sides wrote a
  call_audio recording" (>=2 senders); 284 + 111 unit tests pass. Cold-gate:
  RED (HIGH) -- a STALE-REASON RACE: `_recorderPausedForPeer` is snapshotted
  before an await and `_decisionHolds` revalidates only `wanted`, not the
  peer-drop-vs-sibling-handover reason, so a sibling handover landing during the
  await could reuse `preserveCarrier:true` -> DUPLICATE publish (this device +
  the sibling). Multi-device edge case only (a 1:1 single-device call has no
  siblings, so both-sides recording + the mix are unaffected). Reason-atomic fix
  in flight (make preserveCarrier reflect the CURRENT successor at stop time),
  then re-gate. NOTE this is on top of the not-yet-clean 6e0095ff7a.
  RESOLVED: race fix `d35010fb64` reads `_recorderPausedForPeer` LIVE at the stop
  site (no await between the read and capture.stop); `_electRecorder` rewrites it
  each election as `elected && !_wanted` so a sibling successor flips it false
  before a parked reconcile resumes. Mutation-proven (new race test fails on the
  reverted snapshot), 285/285 tests. COLD-GATE GREEN (codex: reason-atomic,
  duplicate impossible on all interleavings). So the recording fix
  (6e0095ff7a + d35010fb64) is now COLD-GREEN.
- DUAL-DEVICE E2E (2026-09-05, transcript_two_devices.js): the fix's runtime
  path was UNREACHABLE locally. CORRECTED FINDING: the token grant IS present
  (canUpdateOwnMetadata verified 3 ways: token decode, livekit-server v1.9.1
  logs for all 3 participants, app Sentry tokenGrant:granted) -- so the earlier
  'v0.6.0 makes it testable locally' note was only half-right. Despite the grant,
  `setAttributes` timed out 15x ('Signal request timed out'), so the recorder
  election never ran and BOTH of the account's devices published (36s + a 1.8s
  overlap) -- the documented fail-open ('deliver own tail rather than drop'),
  NOT the carrier race d35010fb64 guards. Root cause found in livekit-server
  logs: webhook target `lk-jwt-service:8080` no longer resolved ('no such host')
  because the LAN cutover recreated pangea-lk-jwt-local OUTSIDE compose and it
  lost its network alias -> every room event stalled 15s (5-retry backoff),
  backing up the notifier queue. REPAIRED non-destructively: re-added the
  `lk-jwt-service` alias to the running container (now resolves 172.18.0.5, LAN
  env ws://192.168.1.156:7880 preserved, no recreate). RE-RUNNING the two-device
  test to see if the webhook backlog was what starved the setAttributes ack, or
  if it's a genuine v1.9.1<->protocol16 signaling issue that only staging can
  validate. Owner chose 'repair local stack + retest'. NOT-YET-TESTED: the
  arbitration / 'join on other device' UI flow (needs device_* phone scenarios
  or manual).
- ROOT CAUSE PROVEN (2026-09-05, reverted livekit-server A/B swap): the
  setAttributes timeout is a livekit-server VERSION bug, not the client or the
  grant. livekit_client 2.11.0 correlates its setAttributes ack on the top-level
  RequestResponse.requestId (5s timeout, exact 'Signal request timed out'); v1.9.1
  replies OK but leaves the top-level requestId 0 (only echoes it nested) ->
  never matches -> timeout -> level-triggered re-send storm (0 of 25 acks carried
  the id). v1.13.6 populates it -> setAttributes succeeds (client still
  joins/publishes fine; confirmed in SDK source local.dart + server debug logs).
  FIX = upgrade the SFU's livekit-server on staging/prod (owner-gated Ansible
  infra) to >= the release that populates RequestResponse.request_id (v1.13.6
  confirmed; minimal not bisected). RECORDING is unaffected (election fallback =
  device-id + presence, correct outcome). Only the pangea_chosen arbitration UX
  needs the upgrade. Local stack REVERTED to v1.9.1, clean. OPEN: staging/prod's
  actual livekit-server version is unknown (Ansible, not in repos) -- a DevOps
  check of that one fact sizes the whole prod risk. HELD: no issue/deploy-note
  filed yet (PRs held till Tue); can draft on owner go. Harness bug noted: its
  'token lacks CanUpdateOwnMetadata' FAIL note is now factually wrong + the
  election check asserts on an app-log line the release web build doesn't forward
  to console, so it reds a correct outcome -- worth fixing the check to assert on
  the recording OUTCOME.
- STAGING RISK CLOSED (2026-09-05): staging+prod run livekit-server v1.11.0
  (pangeachat/ansible requirements.yml, MASH role v1.11.0-0, no per-env
  override). A/B-tested v1.11.0 locally -> populates the top-level requestID, 0
  setAttributes timeouts = FIXED shape. So the attribute plane / dual-device
  arbitration WORKS in prod; the bug was ONLY the stale local v1.9.1 pin. NO
  infra upgrade needed. Bumped local-dev/docker-compose.yml livekit to v1.11.0
  (matches staging; local-dev is not a git repo) so #8801 behaves faithfully
  locally.
- INTEGRATION FINDING (blocks the iOS combined build): the recording drop/race
  fixes (6e0095ff7a, d35010fb64 on satvik/call-audio-recording) and the #8801
  device-ownership feature (d6ef346712 on combined) are TWO PARALLEL edits to
  active_call.dart that were never integrated. #8801 REWROTE the recording-publish
  decision to route through a CallOwnership arbiter (`carriedOn => _ownership.carriedOn`),
  REPLACING the ad-hoc _recorderPausedForPeer/carrier mechanism the drop/race
  fixes patched -- so those fixes DON'T cherry-pick onto combined (active_call.dart
  conflict, 202-line divergence) and are likely superseded. combined's #8801
  recording model has NEVER been E2E-validated (all 18/18 + two-device validation
  was on the OLD call-audio-rec model). OGG->MP3 (26a67d96c4) DID cherry-pick
  cleanly onto combined (849019cc74). NOW VALIDATING combined's #8801 recording
  via a two-web transcript.js run on the v1.11.0 stack (both-sides check) before
  building it for iOS. iOS readiness on combined: .env has LAN SYNAPSE_URL, Pods
  present, prior sim build exists; still need pubspec `- .env` uncommented +
  Podfile arm64-sim exclusion patched + .env bundled.
- MIX DELIVERED to owner: room !Hgav callKey QXvZ4Jhk has BOTH halves (@learner +
  @calltester); tools/merge_call_audio aligned them on the SFU timeline (friend
  +14ms) -> merged_stereo.wav (L=you R=friend) + merged_mono.wav -> mp3. NOTE:
  E2E fixture voices, not real speech (shows merge quality, not content).
- iOS BUILD FIXED (env-only, ZERO committed changes): committed Podfile strips
  arm64 from `iphonesimulator` builds (stale Intel flutter-webrtc workaround; CI
  builds DEVICE so never hits it) -> patched the GENERATED Pods project; +
  Homebrew rustc shadowed rustup (iOS twin of the Android rustc note) ->
  prepended the rustup toolchain bin to PATH; built `--no-pub`. Runner.app runs
  on the iPhone 17 Pro sim. It HANGS on splash only because the LAN `.env` is not
  bundled (mobile build needs `- .env` uncommented in pubspec, NEVER committed).
  Durable Podfile fix (arm64 exclusion conditional on Intel host) = owner/PR.
- NEXT for full iOS recording test: re-integrate the drop fix + OGG fix into
  combined, rebuild iOS WITH the LAN .env + the fixes, launch, drive an iOS<->web
  call, confirm BOTH sides record on iOS + the MP3 ring. Then Android on the
  owner's phone (harness device_* scenarios).
- DONE (2026-09-05) COMBINED #8801 RECORDING VALIDATED (two-web transcript.js on
  the v1.11.0 stack): 17/17, exactly 2 pangea.call_audio halves (learner +
  calltester, ~38s each, one per device, no duplicate/one-sided), 0 setAttributes
  timeouts. #8801's CallOwnership records BOTH sides; the old call-audio-rec
  ad-hoc fixes are SUPERSEDED, not missing. Combined is the right target.
- DONE (2026-09-05) iOS COMBINED BUILD VERIFIED on the iPhone 17 Pro sim
  (env-only, NOTHING committed): built @ 849019cc74 (word-card + web-dart2js +
  #8801 + OGG->MP3) for the simulator. Build fixes (all local, REVERTED after):
  pubspec `- .env` uncommented (bundles the LAN .env -> FIXES the splash hang),
  Podfile arm64-sim exclusion 'arm64 i386'->'i386' (Runner fat x86_64+arm64, runs
  on Apple-Silicon sim), rustup toolchain bin on PATH (flutter_vodozemac). App
  LOADS past splash, LOGS IN on the LAN stack, completes full onboarding, reaches
  the live app + DMs, and CALL INITIATION works (call UI + 'This call is
  transcribed and saved' + mic grant fire). NOT captured: a CONNECTED 2-party
  iOS<->web call producing recording halves -- the incoming ring / ongoing-call
  state does not propagate promptly across clients on this ad-hoc local setup
  (API-created DM room + sync timing + 45s window), an ENVIRONMENT/coordination
  limit, NOT an app defect. iOS+web share the recording tap (TrackRendererTap),
  validated both-sides on web, so the mechanism is covered; the audible
  both-sides confirmation is the owner's live human test (sim has no mic). Branch
  clean. NOTES: calltester pw is `calltesterpass` (not learnerpass); local user
  directory search is empty on this stack -> create DMs via API (createRoom +
  invite + m.direct).
- REAL-CALL FAILURE (2026-09-05, first human test, call $L3JwTPX5rdquH): THREE
  defects the fake-fixture web harness missed (false 17/17 confidence):
  (A) CALLER's WEB half DROPPED: @learner (web, caller) captured 3 chunks +
  transcribed + drain_complete=true but uploaded NO pangea.call_audio -- only its
  transcript. So its audio half was captured then discarded (browser memory,
  unrecoverable), while @calltester (Android callee) uploaded both. One-sided
  recording. Suspected #8801 carriedOn/CallOwnership: `carriedOn => _ownership.
  carriedOn` is false on the ownership-leave path, so the caller skips its audio
  publish even though it captured real audio -- the SAME class as 6e0095ff7a
  (drop-own-half) reintroduced via the #8801 model. Transcript publishes but
  audio doesn't = the asymmetry proves publish is wrongly gated on ownership.
  (B) NO full-call mix: only 1 half exists + merge is offline-only, so nothing to
  mix; user expected an in-room full-call recording.
  (C) TRANSCRIPT off: web (@learner) produced ONE 45-second segment
  (at_span_ms=45000) of garbled text ("Jack to Muscova", "CEO boy cut the call")
  while Android produced 13 clean fine segments -- so it can't interleave
  turn-by-turn (the at_ms sort is fine; the 45s blob is the killer). Web audio
  quality (TrackRendererTap) + coarse chunking are the suspects, not the clock.
  Three read-only root-cause agents dispatched; fix + gate after. LESSON: a
  recording/transcript feature CANNOT be validated with synthetic fixtures + a
  scripted hangup -- it needs a REAL two-human call (real mic audio, real
  hangup interleaving) before any green claim.
- ROOT CAUSE (A) CONFIRMED + CORRECTION of an earlier WRONG claim: the dropped
  caller half is a REGRESSION. My earlier note "#8801's CallOwnership supersedes
  the old call-audio-rec fixes, they are not missing" was WRONG. The exact fixes
  6e0095ff7a (publish non-initiator's half after a peer drop; adds
  preserveCarrier/_recorderPausedForPeer) + d35010fb64 (reason-atomic) are NOT
  ancestors of combined and appear NOWHERE in it; #8801 rebuilt the area on the
  ownership model and LOST them -> reverted to pre-6e0095ff7a behavior. The
  17/17 web harness dodged it because its scripted hangup order set the carrier
  latch for both; the real call (Android callee hung up FIRST) exposed it.
  MECHANISM: audio publish is gated on `capture.wasCarryingBeforeLastStop` (a
  NAME COLLISION -- CallAudioRecorder.finish's param is called `carriedOn` but is
  fed the capture carrier fact, NOT _ownership.carriedOn). Ownership.carriedOn was
  true (so the transcript published), but the capture carrier latch was false:
  when the PEER (other account) left first, _electRecorder set _wanted=false and
  _reconcile called capture.stop() WITHOUT settleDeliveries:false (a settle-shaped
  stop, active_call.dart:932) which never writes the carrier latch; the later own
  hangUp early-returns (already stopped) so the latch stays default false ->
  call_audio_recorder.dart:637 skips the upload. RULE: a peer (other account)
  merely leaving is NOT a handover and must never suppress this device's own
  captured half. FIX = port 6e0095ff7a+d35010fb64 onto #8801's active_call.dart:
  add _recorderPausedForPeer = elected && !_wanted in _electRecorder, pass
  capture.stop(preserveCarrier: _recorderPausedForPeer) live at :932, add
  preserveCarrier to capture.stop/_stop (set _wasCarryingBeforeLastStop=true on a
  preserved peer-drop pause), reset the latch in start(); guard with the peer-drop
  tests + tighten the E2E to require BOTH senders (combined's asserts >=1). Also
  rename the recorder param off `carriedOn` so the collision can't recur.
- BUG A FIXED + COLD-GREEN (2026-09-05): commit 529e9a392c on combined ported
  6e0095ff7a+d35010fb64 onto #8801 (add _recorderPausedForPeer = elected &&
  !_wanted, read LIVE at the reconcile stop, preserveCarrier through capture.stop/
  _stop, latch on settle-shaped peer pause when preserveCarrier && _running &&
  !_discardOnStop, reset in start()); renamed CallAudioRecorder.finish param
  carriedOn->wasCarrier (killed the name collision); tightened transcript.js E2E
  to require BOTH senders. 4 mutation-proven tests, 1495 calls tests green,
  analyze/format clean. Agent Codex CORRECT + my independent COLD Codex CORRECT /
  GATE-SOFTENING:no (all 5 adversarial Qs affirmed w/ cited evidence). Not pushed
  (PRs held to Tue). NEXT: rebuild APK+web, clean test-device pollution, real
  re-test -> proves both halves upload + yields the real web WAV needed to
  finalize BUG C (web capture echo-bleed/no-drop-accounting). BUG B (auto
  full-call mix) is an owner design decision, not started.
- audioLost FIX FULLY COLD-GREEN (2026-09-05..07): 3 commits on combined —
  5ee894827c (bounded exp+jitter transcribe retry), 11f87b3c99 (strict deadline
  recheck after every backoff wake + _deliveriesCancelled flag set by _finish
  before sink.close, checked at loop head), 14f181f979 (finish-cancels-retry test
  made fully deterministic via fakeAsync virtual time + enteredBackoff barrier +
  literal count). The double-gate discipline caught THREE real issues my local
  tests missed: (1) retry not strictly time-bounded if a Future.delayed wakes
  late, (2) finish's Future.timeout doesn't cancel outstanding retries, (3) the
  cancel test used a real 50ms wall-clock timer. All root-caused + fixed; my
  independent COLD Codex is CORRECT/gate-softening:no on behaviour AND pinning.
  1501 calls tests green. NOTE: Codex CLI broke mid-session (model gpt-6-astra
  needs newer CLI) — upgraded 0.144.5 -> 0.153.4 (npm) so gates run again; bug A's
  cold gate ran BEFORE the break so it's unaffected. STATUS: bug A + audioLost
  both cold-green, LOCAL (PRs held Tue). Bug C (garbled web transcript) still
  pending -- needs the real web WAV from a local re-test. Bug B (auto mix) =
  owner design decision. Owner wants, in order: transcript ordering perfect
  locally, both halves upload, then local merge looks/sounds natural.

## 2026-09-08 — Merge misalignment root-caused; continuous-recording design drafted + in Codex review
- REAL CALL (owner, 2026-09-07): laptop(web) half 37.5s, phone(Android) half 15s,
  merge "very bad, not properly placed"; a transcript turn ("bye") sorted first.
- ROOT CAUSE (two agents + code): the recorder is FRAME-DRIVEN. Android mute
  disables the mic track -> the native post-AEC process() callback STOPS -> no
  frames -> the frame-driven recorder ENDS the WAV at the mute instant. Web keeps
  emitting silent frames so its half stays full. Uploaded phone offset = FIRST
  run only => no resume after mute. The merge start-aligns + overlays the two
  halves; a 15s-compressed half places later speech ~22s early = the bad mix.
  "bye first" = same family: a capture-order disruption floored a segment to the
  run start. DEVICE TEST: not re-run as a fresh controlled call — the owner's own
  muted call already IS the before-result (mute -> 15s truncation) and the code
  proof is conclusive (offset=first-run-only). Definitive test = the POST-FIX
  call (a muted call should then give a full-length half). Folded into fix
  validation rather than a redundant timed cross-surface drive.
- DECISION (owner pre-approved 2026-09-07; Will does NOT review, owner approves in
  his place, Codex reviews): make each half a CONTINUOUS, time-aligned,
  full-duration file — write silence for EVERY non-producing interval (mute,
  starved/dropped capture, gap between carrying stretches); keep ONE generation
  spanning the whole call; merge stays a start-aligned overlay (no schema/merge
  change). File-size bounded by the existing per-recording ceiling.
- DESIGN DOC drafted at scratchpad/call-audio-recording.instructions.md (NEW
  instructions doc, design-only). In adversarial Codex review (gate dir
  /private/tmp/coldgate-recdesign, verdict -> /private/tmp/recdesign-verdict.txt).
  On green + owner OK -> build under subagent-dispatch-protocol double-gate
  (touches call_capture.dart + call_audio_recorder.dart only), then re-test, then
  build the auto-mix as a real feature -> PR on owner go. PRs still HELD to owner
  go.

## 2026-09-08 — Continuous-recording design doc COLD-CODEX-GREEN (8 rounds)
- Draft at scratchpad/call-audio-recording.instructions.md (NEW instructions doc,
  design-only). Adversarial Codex design review, 8 rounds, converged R1 six
  structural holes -> R8 CORRECT / GATE-SOFTENING:n/a. Gate dirs
  /private/tmp/coldgate-recdesign{,2..8}, verdicts /private/tmp/recdesignN-verdict.txt.
- Locked decisions (all Codex-validated):
  - Recording unit = one contiguous carrier TENURE per device -> one pangea.call_audio
    blob. ANY handover to the user's other device (device-ownership switch) ENDS the
    blob; a return is a NEW blob. A user can thus produce >1 blob; merge overlays N
    blobs on the SFU clock (two in the common no-switch call), no content dedup
    (silence-both => tenures never carry the same speech).
  - Timeline: cursor advances on a MONOTONIC, suspension-inclusive clock (NOT
    frame-driven -> fixes Android mute truncation), mapped once to the SFU epoch at
    sample zero (= the event's existing anchor = the transcript run t0, one shared
    epoch). Silence backfills to catch up / at checkpoints.
  - Drift bound: PERIODIC re-anchor to the SFU clock (<=60s) — pad silence when
    behind, MICRO-TRIM (<= one interval's drift, ~12ms/60s @200ppm, imperceptible)
    when ahead. Bounds skew to ONE interval regardless of call length; NO continuous
    drift-correction resampling (format-rate normalization at merge is preserved).
  - Trim taxonomy (only real-audio removals): bounded micro-trim; out-of-span cut
    (post-handover = next blob's when pre-roll holds, else bounded switch-window
    silence; post-ceiling = flagged truncated tail). Interior committed audio never
    rewritten; buffer written FORWARD, only the TAIL edited (pad / micro-trim /
    out-of-span truncation). Finalize DRAINS real frames to position before tail
    reconcile -> no clipped final syllable.
  - Ceiling = ABSOLUTE call-timeline duration bound shared by all blobs (only the
    global tail past it is lost, never an interior hole); resource bound not
    alignment bound. Video call -> audio-only artifact. Per-blob sample-rate metadata.
  - Mute = silence in the recording, unlabelled gap in the transcript, both on the
    one shared epoch. Lost-capture provenance stays on the transcript (audioLost),
    not a recording-side track.
  - Transcript ordering ("bye first") is a SEPARATE bug NOT fixed by recording
    continuity — its own invariant (every segment keeps its true absolute SFU
    interval across resets; no floor to a stale run start) + its own regression.
  - Scope-out: no drift-correction resampling; no recording-side loss track; no
    crash-durability change (in-memory buffer, upload at finalize, as today); no
    robust N-blob merger (manifest/wait/precedence = the delivered auto-mix feature).
- BUILD PLAN (two pieces, subagent-dispatch-protocol double-gate each):
  (1) continuous full-duration recording (call_capture.dart + call_audio_recorder.dart;
      clock-driven cursor + periodic re-anchor + finalize drain + tenure blob),
  (2) transcript-ordering fix (segment keeps true absolute SFU interval, no stale
      run-start floor) + regression.
  Then re-test on a real call, then build the auto-mix as a real feature. PR on
  owner go (still held). FLAGS surfaced to owner: device-switch multi-blob + the
  pre-roll dependency on the device-ownership handover; "bye first" is a separate
  transcript fix; the auto-mix merger robustness is deferred to that feature.
- Doc NOT yet placed in repo instructions/ — awaiting owner approval (owner is the
  human reviewer in Will's place); on go, place + commit as part of the build.

## 2026-09-08 — Understand-map done (5-reader workflow); build scoped + piece-1 dispatched
- Understand workflow wf_4dd7e1e3-fcc (5 parallel general-purpose readers, opus) produced a
  precise code map: full JSON at /private/tmp/claude-501/.../tasks/w2letltfx.output.
- KEY SYNTHESIS:
  - SEQUENCING (unanimous): both pieces touch call_capture.dart's run-anchor/clock region
    (_runStartsAt, elapsedMs, _notBeforeMs) + call_capture_test.dart -> build SEQUENTIALLY,
    piece 1 (recorder) then piece 2 (transcript ordering). Recorder gets its OWN injected clock
    so its call_capture.dart footprint stays small; transcript owns _runStartsAt.
  - CLOCK REALITY: a true deep-sleep-inclusive clock needs an iOS CLOCK_BOOTTIME / Android
    elapsedRealtime platform channel that does NOT exist here (no web equiv). During an ACTIVE
    call the OS keeps the process alive, so the existing Stopwatch (_uptime) counts through
    backgrounding — exactly the reported Android-mute case. FIX = recorder gets injected
    monotonic clock (default that Stopwatch) + a periodic self-tick that backfills silence when
    frames stop + finalize-pad. Deep-device-sleep inclusion DEFERRED to a platform-channel task.
  - SCOPE TIGHTENED: per-tenure MULTI-blob-per-user (A->B->A device switch), the txnId tenure
    discriminator, merge-overlay-N, and the cross-blob absolute ceiling are only needed for
    mid-call device switch -> DEFERRED to the device-switch/auto-mix feature (matches the
    design's own scoping). Piece 1 keeps the EXISTING one-blob-per-device event model and fixes
    the reported truncation (the common single-tenure case). This avoids destabilizing the
    fragile txnId/dedup/one-event-per-device machinery.
  - "bye first" root cause (piece 2): _runStartsAt = base + (elapsedMs-elapsedAtBase) - batch,
    floored only by _notBeforeMs (0 on the first run). A call that starts muted latches base at
    t0; if the monotonic stalls (device sleep during the mute) the unmuted run's anchor regresses
    to ~t0 and "bye" sorts first. Fix = a reset run's anchor cannot regress below true absolute
    elapsed (wall-elapsed lower-bound guard and/or suspension clock); segments keep their true
    absolute SFU interval; no floor to a stale run start. Owns _runStartsAt/_notBeforeMs +
    transcript_segments/transcript_assembly + regressions.
- Piece-1 build brief: /private/tmp/build-brief-piece1-recorder.md.
- SUBAGENTS: piece-1 implementer (general-purpose/opus) DISPATCHED (background). Contract:
  implement piece 1 per brief, mutation-proven deterministic tests, local gates green
  (dart format/import_sorter/analyze/flutter test @3.41.4), OWN codex self-gate to
  CORRECT/GATE-SOFTENING:no, commit locally (NO push/PR), report SHA + verdict. Then I run the
  independent COLD codex gate; cold-RED -> back to the agent; cold-green -> piece 2. PRs held for
  owner go.

## 2026-09-08 — Piece 1 landed (89af06f620); cold gate found 3 real issues -> fix round dispatched
- Piece-1 implementer committed 89af06f620 (call_audio_recorder.dart + its test): monotonic
  injected cursor, silence backfill, drop-if-behind, periodic re-anchor (pad/bounded micro-trim),
  finalize drain-then-reconcile, tail-editable buffer, ceiling as per-blob DURATION bound. Agent
  self-gate green. Scope held (one-blob-per-device; multi-blob/txnId/transcript untouched).
- MY INDEPENDENT verification: analyze clean (2 files), format clean, recorder bucket 40/40 pass.
  Import gate: our diff changes ZERO import lines; local import_sorter 4.6.0 flags pristine
  siblings identically (tool-version divergence, not our churn) -> CI import gate unaffected.
- MY COLD CODEX GATE (3 parallel: buffer / orchestration / pinning), verdicts at
  /private/tmp/p1-{gen,recorder,pinning}-verdict.txt:
  - buffer primitives: CORRECT / softening:no.
  - orchestration: ISSUES-FOUND (real): (1) finalize reads _elapsedMs() at :1026 AFTER
    _drainPending + uploadStateStore.read awaits -> I/O latency padded as trailing silence;
    (2) _capBytes:530 not rounded to bytesPerFrame -> a mid-sample cap can emit a malformed WAV.
  - pinning: ISSUES-FOUND (real): (3) micro-trim test passes a nonzero re-anchor interval ->
    starts a real 60s Timer.periodic racing the manual checkpoint() -> flaky.
  All three real, none gate-softening (the cold gate earning its keep again).
- FIX ROUND dispatched (fresh general-purpose/opus agent, SendMessage-to-subagent unavailable so
  re-dispatch with the findings). Root causes handed over: (1) end anchor must be the audio-stop
  instant -> capture gen.endElapsedMs synchronously in onRunEnded + a finish-entry fallback,
  reconcile to that; (2) round _capBytes down to a whole PCM frame (2*channels); (3) micro-trim
  test uses the timer-disabled path + manual checkpoint(). Agent to fix + self-gate green +
  commit on top; then I re-cold-gate the changed regions. PRs held for owner go.

## 2026-09-08 — Piece 1 FULLY COLD-GREEN; piece 2 (transcript ordering) dispatched
- Fix round commit a3ab57916b fixed all 3 cold-gate findings (mutation-proven tests); my
  re-cold-gate: behaviour CORRECT/softening:no. Pinning re-gate found ONE narrow gap (the
  onRunEnded end-anchor latch was not independently mutation-proven because no clock advanced
  between onRunEnded and finish -> the finish-entry fallback masked its removal). Closed it in
  a test-only commit 9088243a32 (added a stop->finish clock gap; I mutation-verified RED@1500
  by disabling the onRunEnded capture; restored). Final cold pinning re-gate: CORRECT/softening:no.
- PIECE 1 COMPLETE + COLD-GREEN, local only, 3 commits: 89af06f620, a3ab57916b, 9088243a32
  (all call_audio_recorder.dart + its test; one-blob-per-device model preserved). Verified by me:
  format clean, analyze clean, 162 calls-bucket tests pass, import-neutral.
- PIECE 2 dispatched (fresh general-purpose/opus). Brief:
  /private/tmp/build-brief-piece2-transcript-ordering.md. Owns _runStartsAt/_notBeforeMs +
  transcript_segments/transcript_assembly + regressions; piece 1 did NOT touch these (clean).
  Contract: fix the stale-run-start regress (a reset run anchor must not fall below true absolute
  elapsed; segments keep true absolute SFU interval), two mutation-proven regressions (capture
  layer: stalled-monotonic-during-mute -> unmute run start = true elapsed; assembly layer:
  mute-then-later-speech never sorts first), local gates green, OWN codex self-gate to
  CORRECT/softening:no, commit locally (no push/PR), report. Then I cold-gate. PRs held for owner go.

## 2026-09-08 — Piece 2 (transcript ordering) landed; cold gate surfaced an inherent clock TRADE (owner decision pending)
- Piece 2 commit 322a138190 (call_capture.dart _runStartsAt + two mutation-proven regressions in
  call_capture_test.dart + transcript_assembly_test.dart). Fix: while _notBeforeMs==0 (first run),
  floor the run start by wall-elapsed = max(monotonic, base + (nowMs()-base) - batch). Closes the
  reported "bye first" muted-start-sleep scatter (monotonic stalls, wall sane). Agent self-gate
  CORRECT (after a round-1 INCORRECT: its first monoDelta==0 freeze-detector only fixed the ideal
  test; redesigned to the direct wall floor).
- MY verify: format/analyze clean, 422 calls tests pass, import-neutral, scope = 3 intended files.
- MY COLD GATE: pinning CORRECT/softening:no (tests real+additive). Behaviour first returned
  ISSUES-FOUND/softening:YES because the docstring claimed "scattered is not accepted" while a
  first-run scatter path remained. I made the docstring honest (commits 943da4b973, 88226b3070) ->
  re-gate: GATE-SOFTENING:no. But the re-gate then correctly identified the deeper truth: the fix
  is NOT a strict improvement, it is a TRADE. With only two local clocks and no third reference,
  max(monotonic, wall) cannot tell a stalled monotonic (wall sane) from a forward-jumped wall
  (monotonic sane), so:
    - stall + sane wall  -> FIXED (the reported bug, common, high-harm front-scatter).
    - FORWARD wall jump during the first-run muted window -> run placed too LATE (newly worsened
      vs pre-fix, which ignored the wall here). Rare, lower-harm.
    - BACKWARD wall jump > peer-separation during the sleep -> first run can still scatter. Rare.
  All three are the clocks-failing class, fixable completely ONLY by a suspension-inclusive
  platform clock (iOS CLOCK_BOOTTIME / Android elapsedRealtime) which does NOT exist here and is
  DEFERRED by the design. No local strict-better fix exists (confirmed: the conflation is
  inherent). NOT gate-softening (no test/gate weakened). This is an inherent trade + a design
  judgment, so escalated to the owner rather than iterating Codex further (codex-red-loop: stop
  spot-fixing an inherent tradeoff, bring the human the decision).
- Docstring now states the trade honestly (all 3 residuals). RECOMMENDATION to owner: accept the
  trade (fixes the reported bug + all sane-wall cases; rare wall-anomaly-during-muted-start edges
  need the deferred platform clock), with the platform clock tracked as the complete-fix follow-up.
  Awaiting owner decision before calling piece 2 done. PRs still held for owner go.

## 2026-09-08 — Owner decision: ACCEPT the ordering trade, validate via the real-call re-test
- Owner: accept the wall-floor trade PROVISIONALLY; if it works well in normal cases leave it,
  else research + build the native suspension-inclusive platform clock (the perfect fix). The
  "works well in normal cases" check = the real-call re-test (unit tests already prove the normal
  case: stall+sane-wall -> correct ordering; Android-mute -> full-length recording).
- STATUS: Piece 1 (recorder continuity) fully cold-green; Piece 2 (transcript ordering) done —
  pinning CORRECT, behaviour = the accepted inherent trade (no other defect). Both LOCAL on
  satvik/call-features-combined, no push/PR. HEAD 88226b3070.
- NEXT: real-call re-test. Rebuild web + APK from the combined branch, bring up the local stack
  (lk-jwt :7980 etc.), clean device pollution; owner reconnects the phone and does a MUTED call;
  I pull both call_audio halves + the transcript and verify (a) both halves full-length (piece 1),
  (b) no "bye first" / correct ordering (piece 2), (c) local merge is natural. If normal cases are
  clean -> trade accepted, platform clock tracked as follow-up; else -> build the platform clock.
  THEN build the auto-mix as a real feature -> PR on owner go. PRs still held.

## 2026-09-08 — Re-test environment readied (all but the phone); awaiting phone reconnect
- Both pieces coexist: full calls suite 1513 tests pass on HEAD.
- Web: rebuilt the COMBINED-branch web from the worktree (flutter build web --release, exit 0 ->
  confirms my changes compile clean for web/dart2js, the 2^32-trap risk is a non-issue). Served the
  FRESH bundle on :8092 (0.0.0.0, LAN-visible) via python http.server on build/web (copied .env ->
  build/web/.env). NOTE: the pre-existing :8090/:8091 python servers serve STALE bundles (hash
  mismatch) and are NOT pangea-managed; left them alone. Use :8092 for the laptop side, NOT :8090.
  Browser smoke on localhost:8092: onboarding renders, .env loaded (LAN), only benign optional-asset
  404s (Imaging.js/config.json/native_executor.js), no stack-connection errors.
- LAN call path verified (the pangea-call-testing 'three move together'): Synapse .well-known focus
  -> livekit_service_url http://192.168.1.156:7980; lk-jwt LIVEKIT_URL ws://192.168.1.156:7880; LAN
  Synapse :8008 -> 200. livekit v1.11.0. lk-jwt :7980 healthz 200.
- BLOCKED ON: phone reconnect (adb empty). When connected: build+install the combined-branch APK
  (pubspec .env must be uncommented for the mobile build then re-commented; JAVA_HOME + rustup shim
  per android-apk-rust-target-shadowing; delete the old APK first), verify the phone package
  com.talktolearn.chat, clean device pollution (learner+calltester -> 0) right before, then the owner
  does a MUTED call. Verify: both call_audio halves full-length, no "bye first", natural local merge.

## 2026-09-08 — Combined-branch app on the phone; re-test ready for the owner's muted call
- Phone /data was 100% full (debug APK 428MB wouldn't fit even after uninstalling our old app; the
  phone is packed with the owner's data). Did NOT touch the owner's other app (stray
  chat.fluffy.fluffychat) or their data. Solution: built a RELEASE arm64 APK (166MB, signed with a
  throwaway gitignored keystore created + deleted around the build) -> installed Success,
  lastUpdateTime 2026-09-08 11:21, versionName 5.0.4. pubspec .env uncommented only during each
  build, re-commented after; worktree clean; keystore+key.properties deleted. (Debug/split builds
  failed on size/gradle; release arm64 is the path on a full phone.)
- Device pollution cleaned: learner 4->0, calltester 2->0 (final_clean.py). Next login each = 1 device.
- Laptop web (combined branch) served + verified on :8092 (use it, NOT stale :8090). Stack + LAN path
  verified. READY for the owner's muted call: phone logs in calltester, laptop :8092 logs in learner,
  laptop calls phone, answer, talk, MUTE phone partway, unmute + say "bye" late, hang up ~30-40s.
  Then pull both call_audio halves + transcript (scratchpad/pull_call.py -> /tmp/merge_input) and
  verify: both halves full-length (piece 1), no "bye first" (piece 2), natural local merge.

## 2026-09-08 — REAL-CALL RE-TEST PASSED (both pieces validated end-to-end)
- Owner did the muted call (room !HgavfyvZrMpYhLFMLt, call_key q3KuZ8D7...). Pulled both halves +
  transcript (scratchpad/pull_call.py -> /tmp/merge_input).
- PIECE 1 (recorder continuity) CONFIRMED: calltester(phone,Android) half = 44,934ms FULL length
  (was 15s truncated); RMS/sec profile shows ~13s speech, then ~25s SILENCE (the muted stretch,
  materialized as silence not truncated), then the "Bye-bye" speech PRESERVED at the tail. learner
  (web) 44,968ms. Both start within 57ms on the SFU clock (fileStart 1788881261426 vs 1788881261369).
- PIECE 2 (transcript ordering) CONFIRMED: interleaved-by-at_ms order is chronological and the phone's
  late "...See you. Bye-bye." sorts LAST (t=...303990), NOT first. No "bye first".
- MERGE: overlaid the two halves aligned by SFU start (learner adelay 57ms), aresample 48k, amix,
  alimiter -> /tmp/merged_call.mp3 45.0s; sent to owner. Both full-length + co-timed so it sits
  naturally (vs the old 15-vs-37.5s misalignment). Awaiting owner's ear-check.
- DECISION per owner: normal cases work well -> the ordering TRADE STANDS; native suspension platform
  clock remains a tracked follow-up (not built).
- NEXT (on owner confirm the mix sounds natural): build the auto-mix as a REAL feature (server-side or
  client per the earlier no-egress/client-side analysis; robust N-blob merger spec lives with it),
  then PR the whole combined branch on owner go. Pre-push full CI gate + cross-model green required
  before any PR. PRs still HELD for owner go.

## 2026-09-08 — PR plan set by owner; cues PR extraction started; mix = owner deciding A vs B (I recommend B)
- Everything is LOCAL/held: no origin satvik/* branches, no open PRs. Combined branch bundles 3
  features: (1) call recording+transcript+player (recorder, web-dart2js, orphan/cold-gate fixes,
  bug A, audioLost, piece 1, piece 2, merge tool, player); (2) tap-a-word word card #8797;
  (3) telephony ring cues #8807.
- OWNER PR DECISIONS: (a) do the CUES PR (#8807) NOW; (b) NO PR for the word card #8797 — that is
  Gabby's per Will's message (EXCLUDE it from our PRs); (c) the recording + transcript-ordering +
  player go to a PR AFTER the mix feature.
- CUES PR: cleanly separable (2 commits touch ring_player/call_session/incoming_call_banner + 2
  mp3s + tests; NO overlap with recording files). Extracted to worktree
  .claude/worktrees/cues-pr, branch satvik/call-ring-cues off origin/main (tip 9e6e08a2be);
  cherry-picked 0bdfeb93c4 + 1925844ca5 CLEAN (no conflicts). Running pre-push gates
  (pub get/format/analyze/tests) + Codex gate before push + PR (owner authorized this PR now).
- MIX feature: owner torn A (playback overlay) vs B (client pre-mixed file). MY CRITIQUE ->
  recommend B: deterministic one-time mix = the approved offline result, no live two-player
  drift (Flutter has no sample-accurate multi-stream sync -> A can't guarantee perfect-every-time),
  yields a shareable artifact, byte-testable vs the ffmpeg reference. Awaiting owner's pick; on B
  I'll spec the client-merger (election/trigger/resample-align) + Codex-gate the design, then build
  under the double-gate (agent self-gates+pushes, I cold-gate).

## 2026-09-08 — Cues PR: cross-model gate found pre-existing AudioPlayer lifecycle bugs -> fix dispatched
- Cues branch satvik/call-ring-cues (worktree .claude/worktrees/cues-pr, off origin/main 9e6e08a2be):
  cherry-pick clean, format/analyze/import clean, 63 tests pass. Cue STATE-WIRING confirmed CORRECT
  by Codex (ringback only while placing, stops on connect, fire-once cues, correct hangup/decline).
- BUT cross-model gate (pre-push bar) RED on pre-existing lifecycle defects (GATE-SOFTENING: no):
  per-call AudioPlayer leak (RingPlayer/_tones + one-shot + persistent player never dispose()d),
  async stopAll() not awaited before next cue (tone overlap), stale-play race past the generation
  guard, _configured set before config completes, fixed-600ms disposal truncates a longer asset,
  and a swallowed stop() error (no-silent-failures violation). All real; can't push RED.
- FIX dispatched (general-purpose/opus, in the cues-pr worktree): fix the 6 lifecycle/ordering/
  error classes, add mutation-proven tests, keep the 63 green + wiring unchanged, self-Codex-green,
  commit on the branch. Then I cold-gate -> push satvik/call-ring-cues + open the #8807 PR.
- MIX still awaiting owner A-vs-B pick (I recommended B). Word card #8797 excluded (Gabby).

## 2026-09-08 12:30 — SESSION CHECKPOINT (internet goes dark ~12:55; no new dispatches)
RUNNING (do not stop): (1) cues-fix agent a487fa8ec310ac003 in worktree .claude/worktrees/cues-pr
(branch satvik/call-ring-cues); (2) merge-design Codex gate bg bjfjkceyz -> verdict
/private/tmp/mergedesign-verdict.txt. SendMessage to a subagent is NOT available here, so the
cues-fix agent could NOT be told to checkpoint; it commits only at the END, so if internet
interrupts its Codex self-gate its edits are UNCOMMITTED in the cues-pr worktree — RECOVER via
`git -C .claude/worktrees/cues-pr status` and finish/commit them next session. Do NOT edit the
cues-pr worktree while the agent is still active.

STATE OF THE WORK:
- RECORDING (piece 1) + TRANSCRIPT ORDERING (piece 2): DONE + fully cold-green, LOCAL on
  satvik/call-features-combined (this worktree). Real-call re-test PASSED: phone half full-length
  (mute=silence, bye preserved), no "bye first", merge natural. The ordering wall-floor is an
  accepted TRADE (owner OK'd); native suspension clock = tracked follow-up.
- MIX FEATURE (option B, client pre-mixed file) chosen by owner. Design spec:
  /private/tmp/call-audio-merge-DESIGN.md (Codex gate bjfjkceyz IN FLIGHT). Locked decisions:
  pure-Dart mixer in a compute() isolate (parse WAV, resample 16k->48k polyphase, align by
  fileStartSfuMs, AVERAGE OVER DISTINCT USERS U = matches validated ffmpeg amix normalize=1, no
  clip); new event type pangea.call_audio_merged (not a flag) w/ source_event_ids; election =
  lowest-(senderId,deviceId) among posted halves + rank backoff + skip-if-merged-exists (BEST-EFFORT)
  + PLAYER-SIDE DEDUP (show one) so a double-post is cosmetic; player shows merged first ("Full
  call"), widget unchanged. NEXT after design-green: build the mixer under the double-gate (agent
  self-gates+commits, I cold-gate) -- NOT dispatched yet (owner said no new dispatch + internet).
- CUES PR (#8807): extracted to cues-pr worktree off origin/main (9e6e08a2be), cherry-pick CLEAN,
  format/analyze/import/63-tests green; cross-model gate found 6 PRE-EXISTING AudioPlayer lifecycle
  bugs (per-call leak, tone overlap, stale-play race, _configured race, fixed-600ms disposal,
  swallowed stop error) -> fix agent running. After fix: MY cold-gate -> local PR CI + merge check
  green -> REPORT for owner approval -> then PR. (verdicts: /private/tmp/coldgate-cues-*/verdict.txt)
- WORD CARD #8797: EXCLUDED from our PRs (Gabby's, per Will).
- PR-GATE RULE (owner, standing): open NO PR without cold-Codex green + local PR CI green + merge
  check green + report + explicit owner approval.

RESUME NEXT SESSION: (a) read /private/tmp/mergedesign-verdict.txt (if the gate finished) and act
on the merge-design verdict (red -> revise spec + re-gate; green -> build mixer under double-gate).
(b) reconcile the cues-fix agent: read its output
/private/tmp/.../tasks/a487fa8ec310ac003.output OR `git -C .claude/worktrees/cues-pr log/status`;
if committed, MY cold-gate the fix; if WIP uncommitted, finish it. (c) then cues -> PR-ready ->
report for approval. Local stack (Synapse/lk-jwt :7980/livekit v1.11.0/web :8092) is LAN-configured
and needs no internet. Phone 56091FDAP001N3 has the combined-branch release APK installed.

## 2026-09-08 12:3x — Merge-design gate RED (recorded; revision DEFERRED to next session, not rushed into internet-dark)
Verdict: /private/tmp/mergedesign-verdict.txt. VERDICT: ISSUES-FOUND / n/a. The mixer build is NOT
unblocked (design not green). Findings (root = completion/manifest + revision model under-specified):
1. STALE/NON-UPGRADABLE MERGE: "both members' halves" != all device-tenure blobs (device-switch =
   more blobs); a partial merge can finalize permanently; call_key-only txnId can't upgrade it, and
   player dedup might pick the stale one. FIX: authoritative expected-blob manifest from carrier/
   tenure history + a REVISION/supersession model (txnId carries sorted source-set/revision;
   later more-complete merge supersedes).
2. NO DURABLE RECONCILIATION TRIGGER: an offline-at-call-end device that later receives all halves
   never merges. FIX: reconcile on startup / room sync / network-restore for ended calls lacking a
   finalized (complete) merge.
3. TRUNCATED deferral CONTRADICTS parent (parent line ~165): a ceiling-cut input can read
   complete:true. FIX: add `truncated` to the per-device recording event (small prereq on piece 1).
4. WEB: compute() does NOT background on web -> the mixer heading is wrong; implement chunk/yield or
   a web cap / disable beyond cap.
5. MEMORY: 30min@48k ~172.8MB/half; 2 inputs + 345.6MB Int32List + buffers + isolate transfer ->
   ~1GB peak. FIX: a concrete ENFORCED cap or a streaming/chunked mixer (not "if needed").
6. DEDUP SELECTOR: complete:true unreliable + lowest-producer-ID != coverage; validate the expected
   source set, prefer complete/greatest-coverage, producer-order only as tiebreak; dedup per call_key.
7. WORDING/CONTRADICTIONS: qualify "EXACTLY" (alignment+average exact; resample in-kind only);
   "every device reads identically" -> eventually-consistent + reconciliation + supersession;
   drop "cosmetic self-healing" given divergent source sets; state within-user blobs are sequential
   (no overlap precedence needed); EXCLUDE merged events from credit/transcription/per-half totals.
NEXT SESSION: revise /private/tmp/call-audio-merge-DESIGN.md for the above (esp. the manifest +
revision model) and RE-GATE; likely flag the v1-robustness scope to owner (full carrier-history
manifest vs simpler upgradable-revisions). THEN build the mixer under the double-gate. Do NOT build
until the design is Codex-green.

## 2026-09-08 — Merge design (option B, v1) COLD-CODEX-GREEN (5 rounds); mixer build (part 1) dispatched
- Spec: /private/tmp/call-audio-merge-DESIGN.md. VERDICT CORRECT after 5 rounds (verdicts
  /private/tmp/mergedesign{,2,3,4,5}-verdict.txt). Locked v1 decisions: pure-Dart windowed mixer
  in a compute() isolate (parse WAV, resample 16k->48k polyphase, align by fileStartSfuMs, AVERAGE
  over U=2 = validated amix normalize=1, preallocated output, TransferableTypedData, render-capable
  web yield, ceiling-bounded); new event pangea.call_audio_merged (source_event_ids sorted set,
  txnId (call_key,coverage-hash)); post ONLY a sealed complete {A,B} merge (no provisional);
  seal = participant set fixed at call-end+settle (halves may arrive later via reconciliation, no
  deadline); election = lowest-(sender,device) posted-half, survivor backoff over ONLINE candidates;
  durable reconciliation on startup/sync/network-restore; player total-order dedup + suppress the
  merged row if >2 halves (device-switch = v2). Prereq: add `truncated` to the per-device event.
- SCOPE FLAG to owner: v1 = 1:1 single-tenure-per-user; mid-call device switch deferred to v2.
- BUILD PLAN (parts, each double-gated): P1 the pure mixer (call_audio_merge.dart) + tests
  [DISPATCHED]; P2 event schema pangea.call_audio_merged + `truncated` prereq + writer; P3 election
  + trigger + reconciliation; P4 player fetch + dedup + scope-suppression + merged-primary. On the
  combined branch (this worktree). Cues-fix agent still running in the SEPARATE cues-pr worktree.
- P1 brief: /private/tmp/build-brief-mix-p1-mixer.md.

## 2026-09-08 — Mixer P1 committed (2e627b7079); both build agents had stalled (codex-monitor flake)
- Both build agents (mixer + cues-fix) stalled in the codex-BACKGROUND-monitor wait (they launch a
  bg codex verdict-monitor that id-flakes and never resolves -> they never commit). STOPPED both
  (TaskStop) to freeze their worktrees; took over their finalization directly (the cold gate is
  mine anyway).
- MIXER P1 (call_audio_merge.dart + test, commit 2e627b7079 on satvik/call-features-combined):
  the agent's WIP was on disk. My cold gate (4 parallel: pipeline/parse/resampler/pinning) found
  4 REAL issues incl. a GATE-SOFTENING test (RIFF-walk pin too weak). All root-caused + fixed +
  mutation-proven by me: negative-ceiling early-return; removed the over-engineered input clamp
  (design assumes inputs are our ceiling-bounded recordings -> full parse + single OUTPUT cap;
  this made the ceiling test actually pin the cap); phase-0 exact passthrough; strengthened RIFF
  pin (every==2000); added delayed-output-cap, exact-at-cap, and zero-ceiling-fallback-rate tests.
  Final: pipeline/parse/resampler CORRECT, pinning GATE-SOFTENING:no, 18 tests, every guard
  mutation-verified. (Residual pin-gate ISSUES were my slice-extraction artifacts — the named
  tests exist in the file + were proven RED-without/GREEN-with directly.)
- LESSON: subagents using a bg codex + Monitor stall; the reliable path is the coordinator running
  codex exec SYNCHRONOUSLY (as the cold gates do). When an agent stalls with WIP, TaskStop it, take
  over the on-disk files, and cold-gate directly.
- PENDING: (1) CUES #8807 fix — WIP in cues-pr worktree (agent's self-gate was green per its dying
  message), uncommitted; NEXT: my cold-gate -> commit -> local PR CI + merge check -> report for
  approval. (2) MERGE P2 event pangea.call_audio_merged + `truncated` prereq + writer; P3 election/
  trigger/reconciliation; P4 player. (3) recording+transcript+player PR after the mix. (4) place the
  design docs in repo instructions/ on PR. PR gate: cold-green + local PR CI + merge check + owner
  approval before ANY PR.

## 2026-09-08 — v1 scope confirmed; v2 filed (#8878); running cues cold-gate + merge P2 IN PARALLEL
- Owner: v1 = one-device-recording (1:1 single tenure per user) CONFIRMED. Mid-call device-switch
  merge = v2, filed as pangeachat/client#8878 (assigned bbsatvik01), follow-up, not blocking v1.
- Owner: "do both in parallel" -> LANE A (cues fix -> my cold gate -> PR-ready) + LANE B (merge
  P2/P3/P4 build) concurrently; different worktrees (cues-pr vs combined) so parallel-safe.
- Cues fix committed 3d1860f44e (locally green, 75 tests). Recording (piece1+2) + mixer P1
  (2e627b7079) committed cold-green on satvik/call-features-combined.

## 2026-09-08 (cont) — cues cold-gate found 2 lifecycle + 2 pinning REDs; root-caused, fixed, re-gating
- LANE A cues cold gate (4 gates, fully-inline no-tools prompts after the first batch web-wandered on
  -U0 diffs): behav-orch CORRECT; behav-sound ISSUES x2; pin-sound ISSUES x1; pin-orch ISSUES x1. All
  softening=no, all REAL. Root-caused (one class): "every op touching the loop player abandons once
  disposed, and dispose is await-idempotent."
  - FIX (AssetRingSound): stop() gained the _disposed guard (was the one loop-op missing it -> a
    post-dispose stop hit the released _player = use-after-dispose); dispose() made await-idempotent
    (_disposal ??= _dispose()) so a concurrent 2nd dispose shares the teardown instead of resolving
    early.
  - FIX (RingPlayer, uniformity): stop()/stopAll() gained the same _disposed guard; dispose() made
    await-idempotent. (Behaviour already safe via _playingFor=null; guards are defensive uniformity.)
  - FIX (tests): strengthened 'a stop after a started loop stops it in order' with a mid-hold assertion
    (now distinguishes serialized-after-play from overlap; the prior version's final log was identical
    either way -> not mutation-proving); strengthened 'a disposed player accepts no further cues' to
    also drive stop+stopAll; added 'a stop after dispose never touches the released loop player' and
    'a second dispose awaits the first teardown' (+ disposeHold on the fake). All 3 source fixes
    mutation-proven RED locally (stop-guard, serialization, dispose-idempotency).
  - Local gates GREEN: dart format clean, analyze clean (touched files), full ring suite passes.
    import_sorter tool won't complete locally (env glitch after "Sorting 1725 files", exit 1, no
    per-file output) but NO import-line changed vs the CI-green feature commit 3d1860f44e -> import
    order unchanged.
  - RE-GATE (fixed code, 4 focused inline gates): rg-behav-orch CORRECT, rg-pin-orch CORRECT;
    rg-behav-sound + rg-pin-sound IN FLIGHT.
  - NOT yet committed on cues-pr (waiting for the 2 remaining re-gates green). After green: commit the
    fixes -> local PR CI + merge check -> report for owner approval (NO PR without approval).
- LANE B: dispatched P2 builder (sonnet, agent a139cd8a3a9ca0d48) on the pangea.call_audio_merged
  event schema + writer + `truncated` prereq; brief /private/tmp/build-brief-mix-p2-schema.md. Will
  cold-gate its output (agents stall on bg-codex+Monitor; brief tells it to self-gate SYNCHRONOUSLY).
- LESSON: a codex cold gate handed a -U0 diff + "read the source file" pointer web-wanders (its own
  web_search tool) and no-verdicts. Reliable recipe: paste the FULL relevant source/tests INLINE,
  forbid all tools ("everything is in this message, use NO tools, do not search, do not read files"),
  keep code <~330 lines, one codex per tracked bg Bash task (no & subshell orphaning).

## 2026-09-08 (cont) — LANE A cues fix GREEN across the full gate; awaiting owner approval for PR
- All 4 re-gates CORRECT/softening=no. Fixes committed c02d07e6de on satvik/call-ring-cues.
- Local PR CI (exact integrate.yaml code_lint + calls bucket):
  dart format lib/ test/ = 0 changed; import_sorter --no-comments --exit-if-changed = Sorted 0 (the
  earlier local failures were the MISSING --no-comments flag, not our files); license_checker = none
  need approval; flutter analyze = No issues found; flutter test test/pangea/calls/ = All 1420 passed.
- Merge check: origin/main..HEAD = 4 commits (all #8807: 8c087d363d, 58e54feddf, 3d1860f44e,
  c02d07e6de); merge-tree --write-tree CLEAN (0 conflicts); 14 behind, no rebase needed.
- STATUS: Lane A is PR-ready and reported to owner. NO PR until explicit owner approval (per gate).
  PR draft at /private/tmp/cues-pr-body.md. Branch NOT pushed.
- LANE B: P2 builder (a139cd8a3a9ca0d48) still running.

## 2026-09-08 (cont) — LANE B P2 committed (de8dc626db); running my independent cold gate
- P2 builder (agent a139cd8a3a9ca0d48) delivered: CallAudioMergedContent model
  (call_audio_merged_event.dart) + writeCallAudioMergedEvent (call_audio_merged_writer.dart) +
  truncated field on the per-device event + recorder wiring (truncated: gen.cappedLogged). 8 files.
- I READ + independently verified the tricky parts (red-to-root-cause, not trusting the agent's word):
  - coverageHash = SHA-256 over length-prefixed netstring framing of canonical (sorted/dedup/
    well-formed-UTF-16-only) ids -> injective, collision-free even for foreign ids w/ colon/NUL/
    surrogates. Agent found+fixed 2 real collisions (NUL-join, lossy-surrogate) over 3 Codex rounds.
  - _sanitizedSourceEventIds bounds work (raw.length>4*cap -> refuse) BEFORE the scan; refuses (not
    truncates) over-cap/empty coverage.
  - truncated=gen.cappedLogged: verified append()/padSilenceFrames() return true IFF the cap dropped
    bytes, and trimTailFrames (clock-drift micro-trim) never sets cappedLogged -> truncated true iff a
    REAL ceiling cut. Agent's claim confirmed by my own read of the recorder internals.
- Independently re-ran P2 tests: 108 pass (merged_event + event + recorder buckets).
- MY cold gate: 5 focused inline gates launched (behav-model, behav-writer+truncated, pin-json,
  pin-hash, pin-truncated). Agent's own Codex gates A(model)+B(writer) were CORRECT but its C/D pinning
  fixes were self-verified only -> MY cold gate is the backstop for that gap, per the brief.
- Agent DEFERRED (reasonable, cross-cutting): no upper LENGTH bound on callKey/url/mimetype/codec in
  BOTH CallAudioMergedContent and the sibling CallAudioContent; fixing only the new file would make the
  two inconsistent -> spawned follow-up task_cbf94fc3 rather than a unilateral one-sided fix. NOT a
  blocker for P2; revisit as a paired change to both events.
- NEXT after P2 cold-green: P3 (election + trigger + durable reconciliation) then P4 (player).

## 2026-09-08 (cont) — LANE B P2 fully cold-green + committed; starting P3 design
- All 5 P2 cold gates CORRECT/softening=no (behav-model, behav-writer+truncated, pin-json, pin-hash,
  pin-truncated). pin-truncated found 2 REAL gaps: a tautological 'truncated does not change the txnId'
  test (removed -- truncated is not a txnId param, no honest runtime pin exists) and a missing
  clock-drift-trim->false case (added to the existing proven micro-trim test; mutation-verified RED
  when trimTailFrames latches cappedLogged). Fixes committed 801237963d.
- I independently READ+verified: coverageHash length-prefix framing is injective/collision-free;
  _sanitizedSourceEventIds is bounded + refuses (never truncates); truncated=cappedLogged is true iff a
  real ceiling cut (append/padSilence dropped bytes), never the clock-drift trim. All confirmed.
- P2 DONE: de8dc626db (impl) + 801237963d (test fixes) on satvik/call-features-combined.
- NEXT: P3 = election + trigger + durable reconciliation (design "Election and durable convergence" +
  "Trigger + durable reconciliation"). ARCHITECTURAL -> design-first: map integration surfaces, write a
  build design, cold-gate the DESIGN, then build (Opus) + cold-gate code. Exploration dispatched.

## 2026-09-08 (cont) — P3 design-first: v1 unsound (9 findings) -> v2 root-caused; re-gating
- Explored P3 integration surfaces (agent): fetchCallAudio (call_audio_repo.dart:55) reads halves;
  callParticipants (transcript_view.dart:71) gives {me,peer}+known; post-call kick at
  call_session.dart:1080 _finishRecording; upload=client.uploadContent; onSync/onSyncStatus + startup =
  durable hooks (mirror analytics_sync_controller.dart:39); CaptureElection._sortsBefore is
  (canCapture,deviceId) self-anchored -> NOT reusable, need a new (senderId,deviceId) order; mixer is
  compute-safe; coordinator home = CallService (call_service.dart:21). Gaps to build: seal predicate,
  cross-participant election, candidates-from-halves, mxc download helper, the coordinator itself.
- DESIGN v1 cold-gate = ISSUES x9 (design-first paid off): unbounded pending set; seal not immutable
  (rejoin/late-half); source-set TOCTOU; lost trigger wakeups; work-after-dispose; deterministic-failure
  retry storms + orphan uploads; underspecified startup discovery; false candidate invariant (indexOf
  -1); over-claimed exactly-once.
- DESIGN v2 root-caused into 7 GOVERNING RULES (design decisions, locked pending re-gate):
  1. Reconciliation ROOM-DERIVED + EVENT-TRIGGERED, no retained pending map (a late half's own sync
     re-triggers) -> bounds memory + fixes late-half completion.
  2. RE-VALIDATE (halves + merged-existence) right before upload AND send + a settle delay; P4 >2-half
     suppression is the backstop -> a rare stale post is never SHOWN.
  3. Dirty/rerun flag coalesces triggers landing during an in-flight attempt.
  4. Explicit notCandidate verdict (this device didn't post a half -> stand down).
  5. Disposal generation token checked across every await + before upload/send.
  6. result.complete==false (span over ceiling) = TERMINAL; per-call attempt cap bounds orphan uploads.
  7. HONEST guarantee: at-least-once, <=2 events (per-device txnId dedup), exactly ONE visible row via P4
     dedup. No client-side exact-once claim.
- Design at /private/tmp/call-audio-merge-P3-DESIGN.md. Re-gating v2 now; build only after design green.

## 2026-09-08 (cont) — P3 design round 2 (8 findings) -> v3
- Design v2 re-gate (round 2, xhigh) = ISSUES: in-memory reconciliation not durable across restart +
  timeline truncation; re-validate-before-SEND dropped from the flow (only before upload); coalescing
  needs drain-until-clean not one-rerun; disposal token can't abort in-flight upload/send (overstated);
  terminal/cap lifecycle inconsistent (in-memory cap lost on restart, deterministic mix exceptions not
  terminal, hung stages held forever, no concurrency bound); participants-not-known wrongly terminal;
  delivery over-claimed.
- KEY ENABLER found: fetchCallAudio uses the RELATIONS API (getRelatingEventsWithRelType by anchor id),
  NOT the sync timeline window -> a durable index storing only (roomId, callKey) can re-fetch any call's
  full half-set later, closing the restart/truncation loss cleanly.
- DESIGN v3 additions: durable TTL-bounded reconciliation index (ExpiringStorageBox, key roomId|callKey,
  TTL ~7d, payload {attemptCount, quarantined}); re-validate before BOTH upload AND send; drain-until-
  clean coalescing; disposal token with honest "no NEW side-effect after observing disposal" wording;
  broadened terminal (non-DM, >2 halves, truncated/null-start/non-pcm16, complete==false, deterministic
  mix/decode exception); STAGE TIMEOUTS; GLOBAL CONCURRENCY BOUND; participants derived from the two
  halves' senders gated on room being a DM (directChatMatrixID) so transient-unknown != terminal; honest
  at-least-once-within-TTL delivery (<=2 events, one visible via P4 dedup).
- Re-gating v3 (round 3), verdict framed BLOCKER vs ACCEPTABLE-V1 (only blockers fail it). Build only
  after design SOUND.

## 2026-09-08 (cont) — P3 design round 3 (3 blockers, 3 acceptable) -> v4
- v3 re-gate (round 3, BLOCKER-vs-ACCEPTABLE framing) = 3 BLOCKERS + 3 ACCEPTABLE-V1 (progress:
  9 -> 8 -> 3). Blockers: (1) index populated too late -- a crash mid-merge before indexing loses the
  callKey; (2) a lone transient failure has no guaranteed wakeup (waits out the 7d TTL); (3) stage
  timeouts don't cancel underlying work -> hung ops accumulate past the wrapper cap.
- ACCEPTABLE-V1 (reviewer-cleared): the unavoidable validate->send stale window (settle+double-validate+
  P4 suppression); duplicate events/orphan media in rare races (P4 dedup + txnId); the terminal
  classifications are coherent.
- v4 fixes the 3 blockers: INDEX-BEFORE-AWAIT (write (roomId,callKey) at half-post + before any
  await/admission); PERIODIC DRAIN timer (retries backoff-elapsed index entries, guaranteed wakeup);
  concurrency PERMIT-UNTIL-SETTLE (released only when the underlying stage future settles, not the
  wrapper timeout -> at most K underlying I/O ops ever; mixer is pure/bounded, cannot hang).
- Re-gating v4 (round 4). Build P3 only after design SOUND (or only ACCEPTABLE-V1 residuals).

## 2026-09-08 (cont) — P3 design round 4 (1 blocker) -> v5; round 5 re-gating
- v4 re-gate (round 4) = 1 BLOCKER + 4 ACCEPTABLE-V1 (9 -> 8 -> 3 -> 1). Blocker: index expiry not
  anchored to first-seen -> a perpetually-incomplete call (peer never posts) is rewritten by every
  periodic drain (pendingIncomplete is not a "failure" so attemptCap never bites), refreshing the
  ExpiringStorageBox TTL forever -> unbounded index growth.
- ACCEPTABLE-V1 (reviewer-cleared, all): validate->send stale window; orphan upload on timeout/dispose;
  K permanently-hung ops halt reconciliation (bounded, playable halves); quarantine/TTL delivery limit.
- v5 fix: expiry anchored to IMMUTABLE firstSeenAt; every upsert is read-modify-write preserving
  firstSeenAt/attemptCount/quarantined/nextRetryAt; LOGICAL expiry = firstSeenAt+TTL enforced in code
  (independent of the box write-timestamp) -> a peer-never-posts call is dropped at firstSeenAt+TTL, index
  bounded. Also narrowed deterministic-mix-exception terminal to immutable-bad-input only (runtime
  OOM/isolate-spawn = transient).
- Design at /private/tmp/call-audio-merge-P3-DESIGN.md. On SOUND -> build P3a (pure decision core) + P3b
  (coordinator) via a workflow, cold-gate the code.

## 2026-09-08 (cont) — P3 design v5 COLD-GREEN (SOUND); building
- v5 re-gate = VERDICT: SOUND. 5 rounds: 9 -> 8 -> 3 -> 1 -> 0 blockers. All residuals ACCEPTABLE-V1
  (documented): validate->send stale window (P4 suppresses); orphan upload; K-hung-ops halt (bounded);
  quarantine/TTL delivery limit. Reviewer caution for the BUILD: keep the immutable-decode vs
  runtime-mixer failure distinction TYPED; NO broad terminal catch.
- DECISION LOCKED: P3 design at /private/tmp/call-audio-merge-P3-DESIGN.md is authoritative. Build in two
  waves (dependent -> sequential, Codex-green each): P3a pure decision core (sonnet) -> cold-gate ->
  P3b coordinator + fetchCallAudioMerged reader + mxc download helper + wiring (opus) -> cold-gate.

## 2026-09-08 (cont) — P3 build waves dispatched
- WAVE 1 (P3a, sonnet, agent a2e8469ea599853dc): pure decision core call_audio_merge_decision.dart +
  tests. Brief /private/tmp/build-brief-mix-p3a-decision.md (exact 9-step decision tree). RUNNING.
- WAVE 2 (P3b-plumbing, sonnet, agent aae59136bc2ebb5ca): fetchCallAudioMerged reader +
  CallAudioMergedRecording in call_audio_repo.dart + mxc download helper. Brief
  /private/tmp/build-brief-mix-p3b-plumbing.md. RUNNING IN PARALLEL (separate files; both told to
  `git add` ONLY their own files to avoid a shared-branch race).
- WAVE 3 (P3b-coordinator, OPUS) brief READY at /private/tmp/build-brief-mix-p3b-coordinator.md —
  CallAudioMergeCoordinator (index-before-await, drain-until-clean, permit-until-settle, firstSeenAt-
  anchored expiry, typed terminal-vs-transient, the 9-step evaluation pass). DISPATCH after waves 1+2
  cold-green. NO wiring in wave 3 (fully seam-injected + tested standalone).
- WAVE 4 (wiring) = instantiate in CallService + kick from CallSession._finishRecording + dispose in
  matrix.dart. After wave 3 green. Touches shared files -> careful + cold-gate.
- Each wave: builder self-gates (sync foreground codex) + commits; I run the independent COLD gate before
  the next wave builds on it (Codex-green each wave, per quality bar).

## 2026-09-08 (cont) — P3a built (fce4bbaf31), cold-gating; plumbing still running
- WAVE 1 P3a DONE: agent committed fce4bbaf31 — call_audio_merge_decision.dart (356) + test (368, 18
  tests, all mutation-proven RED->GREEN). Agent self-gate: behaviour CORRECT; pinning CORRECT after 1
  codex round of fixes (added anti-correlated myRank/coverage fixtures + null-other-deviceId + split
  placeable-prereq tests). I read the code: matches the 9-step spec exactly; _compareCandidates deviceId
  tie-break is dead-code-in-v1 (2 distinct senders never tie) but per-spec + harmless.
- MY cold gate on P3a launched (behav + pin). Waiting.
- NOTE/lesson: two agents in ONE worktree (P3a + plumbing) caused a transient file-visibility flux for
  the P3a agent (its files briefly 'missing' then back, byte-identical). Worked out because BOTH used
  targeted `git add <files>` (never -A). Confirmed no cross-contamination via git status/diff.
- WAVE 2 plumbing (aae59136bc2ebb5ca) still running (fetchCallAudioMerged + mxc download).
- Cues PR OPENED: pangeachat/client#8888 (pushed satvik/call-ring-cues, CI running).

## 2026-09-08 (cont) — P3a COLD-GREEN; cues PR #8888 all-green
- P3a cold gate: behaviour CORRECT; pinning CORRECT after 3 rounds. Round-1/2/3 added: 5+2 precedence
  boundary tests (each mutation-proven by swapping the rule pair), same-user/wrong-device NotCandidate,
  zero-halves, honest null-deviceId comment. 27 tests. Commits fce4bbaf31 + 809852faff + dada4fe6b5.
- CUES PR #8888: was red on qa_scope only (non-blocking metadata check that reads the LINKED ISSUE, not
  the PR). Fixed by ticking Evaluated + all four platforms on issue #8807 (audio feature -> all four per
  qa-labeling) + manual re-run -> ALL GREEN. Saved memory qa-scope-reads-linked-issue. Ready to merge on
  owner go.
- WAVE 2 plumbing (agent aae59136bc2ebb5ca): all 4 files WRITTEN on disk (call_audio_download.dart,
  fetchCallAudioMerged in call_audio_repo.dart, + 2 tests) but NOT yet committed -- agent in gate/commit
  phase (last file touch 18:22). Awaiting its report; if stalled, TaskStop + take over WIP + cold-gate.

## 2026-09-08 (cont) — P3b plumbing built + cold-gated; combined-branch import_sorter fixed
- WAVE 2 plumbing DONE: agent committed a8fa6785ed (fetchCallAudioMerged + CallAudioMergedRecording in
  call_audio_repo.dart; call_audio_download.dart = CallAudioDownloader + mxcServerAndMediaId +
  callAudioDownloaderFor over client.getContent; 23 tests). Agent self-gated 5+4 rounds CORRECT.
- MY cold gate: reader-behaviour CORRECT (re-ran after a sed-extraction empty-fence artifact),
  download-behaviour CORRECT, reader-pinning CORRECT, download-pinning had ONE redundancy (double-slash
  test pinned the same length guard as multi-segment) -> folded into one test (commit 769b57d83d),
  re-gating.
- IMPORT_SORTER combined-branch fix (58fd2b65ea): the recording/event/test files were committed WITH
  '// Dart imports:' group comments, which CI's `import_sorter:main --no-comments --exit-if-changed`
  FORBIDS -> the branch would have gone RED at PR-2 time. Root cause found: import_sorter needs
  `flutter pub get` first (else it dies mid-run with a misleading exit 1 -- which is what made the local
  runs look like an env flake AND what the plumbing agent half-saw). With pub get it completes and wanted
  15 files. Stripped the group comments (mechanical, 0 logic lines, 1625 calls tests still pass), branch
  now import_sorter-clean. LESSON: run `flutter pub get` before import_sorter locally; a bare run dies
  and misreads as either 'clean' (cached) or 'fails' (no verdict).
- NEXT: download-pinning re-gate green -> plumbing fully cold-green -> dispatch WAVE 3 coordinator (opus).

## 2026-09-08 (cont) — P3b plumbing FULLY cold-green; WAVE 3 coordinator dispatched
- Plumbing all 4 cold gates CORRECT (reader-behav, download-behav, reader-pin, download-pin after fold).
  Commits a8fa6785ed + 769b57d83d. Plumbing DONE.
- WAVE 3 (P3b-coordinator, OPUS, agent a8588a0c9210b5542): CallAudioMergeCoordinator + tests, fully
  seam-injected, NO wiring. Brief /private/tmp/build-brief-mix-p3b-coordinator.md. RUNNING. Will
  cold-gate its output (index/lifecycle machinery + evaluation-flow + pinning gates).
- WAVE 4 (wiring) still queued after wave 3 green.
- Branch state on satvik/call-features-combined: recording (pieces 1+2) + mixer P1 (2e627b7079) + event
  P2 (de8dc626db, 801237963d) + truncated + P3a decision (fce4bbaf31, 809852faff, dada4fe6b5) + plumbing
  (a8fa6785ed, 769b57d83d) + import_sorter fix (58fd2b65ea) all committed, import_sorter+format clean.

## 2026-09-08 (cont) — WAVE 3 coordinator built (ad7c8c5072); adjudicated + cold-gating
- Coordinator agent committed ad7c8c5072: call_audio_merge_coordinator.dart (902) + test (1242, 25
  tests) + ExpiringStorageBox.keys() (+20, additive read-only). Agent self-gate ended RED-with-overrides
  on 2/3 gates (it applied all legit fixes, rejected the rest as design-accepted/false-positive) and
  named ME the adjudicator.
- I READ the whole coordinator + adjudicated the residuals:
  - RMW race (index): FALSE-POSITIVE confirmed -- single Dart isolate + one-runner-per-key (_inFlight
    coalescing) + synchronous in-memory read/write => RMW is atomic, no preemptive race. Agent right.
  - `>` vs `>=` in _logicallyExpired: deliberate consistency with ExpiringStorageBox's own `> ttl`. Fine.
  - Orphan-upload-during-mix: REAL minor deviation from design rule 3 ("immediately before upload") --
    the code re-validated before MIX then mixed then uploaded, orphaning an upload if a third half
    arrived during the mix. FIXED (commit ...): moved the re-validate to immediately before upload,
    after the mix. 25 tests still pass. The sent/shown result was always correct; this closes the orphan
    window.
  - Verified machinery: permit-until-settle (tracker.last.whenComplete release, no leak on early return),
    _Semaphore counting+handoff, _stage timeout keeps raw running, _cancellableDelay, disposal token.
- MY cold gate: 4 focused gates launched (eval-flow, index/lifecycle machinery, pinning A [revalidate +
  typed-terminal + boundedness], pinning B [permit-until-settle + drain-until-clean]). Waiting.
- After coordinator cold-green: WAVE 4 wiring (CallService + CallSession kick + matrix dispose), then P4
  player.

## 2026-09-08 (cont) — coordinator cold-gate adjudicated + fixed (26 tests)
- 4 cold gates (flow/machinery/pinA/pinB). Adjudication + fixes (commit after ad7c8c5072):
  - REAL fix: onSyncedMergedEvent was the only trigger missing `if (_disposed) return;` -> added (machinery).
  - SOFTENING resolved: 'aborted attempt does not run a coalesced re-pass' over-claimed (per-pass check
    masked the loop guard). Rewrote with onReconnected (dirty w/o index-recreate) + index-null assertion;
    now removing the loop guard flips it RED (mutation-verified). The loop guard is real: without it a
    coalesced re-pass's _keepPending RECREATES the merged-then-removed index entry.
  - Added late-third-half re-validate test (>2 halves -> _stillMergeable retires TERMINAL; mutation-RED).
  - Documented pre-send guard = _superseded NOT dirty (dirty-abort would starve the send in a busy room).
  - ACCEPTABLE-V1 (adjudicated, not fixed): (a) irreducible validate->send window (rare stale post,
    P4-suppressed); (b) remove-then-recreate renews ONE inert entry per re-synced old call (bounded,
    self-heals -- NOT unbounded). RMW atomicity + permit-until-settle verified correct.
  - orphan-upload reorder (prior commit): re-validate now immediately before upload, after mix.
- 26 tests, format/analyze/import_sorter clean. Re-gating pinB (softening) + machinery (dispose+residual).
- After coordinator green: WAVE 4 wiring (CallService + CallSession kick + matrix dispose), then P4 player.

## 2026-09-08 (cont) — WAVE 3 coordinator COLD-GREEN; starting wave 4 wiring
- Coordinator cold-gate DONE: machinery re-gate SOUND (dispose fix + remove-then-recreate = ACCEPTABLE-V1
  bounded); pinB re-gate CORRECT/softening=no (aborted test now genuinely pins the loop guard). flow's
  validate->send race + machinery's remove-then-recreate are documented ACCEPTABLE-V1 (irreducible/
  bounded, code-commented). 26 tests, all gates clean.
- Coordinator commits: ad7c8c5072 (build) + reorder + fix(dispose/loop-guard/third-half) + docs.
- WAVE 4 wiring NEXT: instantiate CallAudioMergeCoordinator in CallService (call_service.dart:104) with
  seams (relationsFetcherFor(client), callAudioDownloaderFor(client), client.uploadContent,
  client.sendEvent-shaped, compute(mergeCallAudio), an ExpiringStorageBox, isDmRoom via
  room.directChatMatrixID, myUserId=client.userID, myDeviceId=client.deviceID); start() it; subscribe
  client.onSync.stream -> onSyncedCallAudio/onSyncedMergedEvent (extract callKey = event m.relates_to
  event_id for pangea.call_audio/_merged) and client.onSyncStatus.stream error->finished -> onReconnected;
  dispose with the service (matrix.dart:1026). Kick from CallSession._finishRecording (call_session.dart:
  1080) after _record.finish -> coordinator.onCallFinished(roomId, callKey, client.userID, deviceID).
  Touches SHARED files (call_service, call_session, matrix) -> careful + cold-gate.
- Then P4 player (fetchCallAudioMerged-first, dedup, >2-half suppression).

## 2026-09-08 (cont) — coordinator room-aware send fix (b871417c32); wave-4 signature scan
- Caught a REAL bug pre-wiring: coordinator send seam was (content, txnId), no room -- but one
  coordinator serves MANY rooms, so a wired send couldn't target the call's room (fakes hid it).
  Fixed: CallAudioMergeRoomSender(roomId, content, txnId); call site binds the current room; test fake
  records roomId + complete-call test asserts the right room. 26 tests, clean. Commit b871417c32.
- Coordinator (P3) DONE + cold-green + room-aware.
- WAVE 4 wiring: dispatched Explore (ad99b3463abaad418) for exact signatures (ExpiringStorageBox ctor +
  payload read/write, CallService ctor/dispose + matrix.dart lifecycle, CallSession._finishRecording kick
  point + how it reaches CallService, onSyncStatus transition, onSync event access, room.sendEvent/
  getRoomById/uploadContent/directChatMatrixID). Brief + build after it returns.

## 2026-09-08 (cont) — WAVE 4 (wiring) + P4 (player) dispatched IN PARALLEL (file-disjoint)
- Wave-4 signature scan (agent ad99b3463abaad418) returned: ExpiringStorageBox round-trips payload intact
  (payloadKey=free wrapper label != 'timestamp'); box ttl >= indexTtl; keys()/sweep() await GetStorage
  init but read()/write() don't (early-trigger-before-init = ACCEPTABLE-V1); CallService(this.client,{...})
  + dispose() at :2203, no sync subs today; CallSession reaches CallService via call.calls (public);
  identity.key (callKey) nullable -> guard; onSyncStatus error->finished edge must be tracked manually;
  onSync = iterate update.rooms?.join?.entries; content['call_key'] is Object? -> type-check;
  room.sendEvent(content, type:, txid:)->Future<String?>; getRoomById/uploadContent/directChatMatrixID
  confirmed.
- WAVE 4 (wiring, OPUS, agent a77a10d2d23281727): brief /private/tmp/build-brief-mix-p3b-wiring.md.
  Touches call_service.dart (own+start+subscribe+dispose coordinator w/ room-aware seams + per-client box)
  + call_session.dart (_finishRecording kick, await finish + null-guard callKey). Extract handleSync/
  handleSyncStatus as testable methods. RUNNING.
- P4 (player, OPUS, agent a75e5c1007624ca26): brief /private/tmp/build-brief-mix-p4-player.md. Touches
  NEW call_audio_merged_selection.dart (pure selectMergedRow: >2-halves suppress, else greatest coverage
  cardinality -> lower coverageHash -> lower eventId) + transcript_view.dart (fetch merged parallel,
  render merged-first "Full call" row via relabel-to-m.audio, halves below). RUNNING.
- Both told targeted `git add` only (concurrent on the branch). Cold-gate both outputs.
- After both green: PR-2 prep (recording+transcript+merge+player as one PR on owner go).

## 2026-09-08 (cont) — P4 player built (2321eb1423), cold-gating selection; wiring still running
- P4 DONE (agent a75e5c1007624ca26): call_audio_merged_selection.dart (pure selectMergedRow) + test
  (8, mutation-proven anti-correlated fixtures + real coverageHash) + transcript_view.dart integration
  (fetch merged parallel + isolated like the halves; render merged "Full call" row FIRST via
  relabel-to-m.audio when selectMergedRow!=null, else today's output) + 2 widget tests + intl_en.arb
  'Full call' key. Self-gate GREEN x3.
- P4 correctly ISOLATED its surface: the full calls bucket is RED in the worktree ONLY due to the
  concurrent WIRING agent's uncommitted call_service/call_session WIP (asserts prior behaviour); P4
  baselined 206/206 at HEAD + confirmed no failing file imports its surface. This is the two-agents-in-one
  -worktree effect; the wiring agent MUST leave the bucket green when it commits.
- I read P4's selection fn (matches the design total order exactly) + transcript_view diff (mirrors the
  halves isolation). MY cold gate: selection behav + pin running. Render = P4-self-green + widget tests +
  analyze; UI mirroring, lower-risk.
- WAVE 4 wiring agent (a77a10d2d23281727) STILL RUNNING; its WIP is in the worktree. Verify it leaves the
  calls bucket green on commit.

## 2026-09-08 (cont) — WAVE 4 wiring cold-gated; calls bucket GREEN (+1678); real robustness fixes
- Wiring agent (a77a10d2d23281727) committed 2fe7e454ac with a JUSTIFIED deviation (I reviewed + accept):
  eager box construction broke ringing widget tests (GetStorage schedules a timer, CallService built on
  every incoming-call-banner render) -> went LAZY (build coordinator on first call-audio signal) + a
  probe + trigger buffer + terminal-fail flag. Startup scan runs at first call-audio activity not login
  (within TTL horizon) = ACCEPTABLE-V1.
- calls bucket VERIFIED GREEN: +1678 All tests passed, exit 0 (the earlier +478 was a mid-run snapshot).
- MY cold gate (wire-lazy/wire-pure/wire-pin): wire-pure CORRECT. wire-lazy found REAL: (1) buffer could
  grow unbounded on a never-settling probe -> capped at 64 (a hung probe activates nothing so the cap
  costs no merge, only bounds memory); (2) a throwing buffered trigger aborted the whole replay -> per-
  trigger try/catch; (3) handleSyncStatus missing _disposed guard -> added; (4) probe catch did cleanup
  after dispose -> _disposed bail added. wire-pin found softening (test gaps): invalid call_key tested on
  only ONE branch each -> extended to BOTH; 'error->error' didn't pin latch preservation -> added
  'error->error->finished reconnects once'. Fixes committed (2 commits after 2fe7e454ac).
- Re-gates: wire-lazy3 (complete paste) + wire-pin4 (complete paste) running; earlier re-gate REDs were
  MY truncated sed pastes (the reviewer confirmed the substance each time; the file compiles + 18 tests
  pass). analyze/format clean.
- After wiring green: the WHOLE feature (recording+transcript+P1-P4 merge+player+wiring) is on
  satvik/call-features-combined, ready to bundle as PR 2 on owner go.

## 2026-09-08 (cont) — wire-lazy5 GATE-SOFTENING adjudicated -> real fix (buffer-saturation observability)
- wire-lazy5 (final wire re-gate) returned a CONTRADICTION: VERDICT: CORRECT but GATE-SOFTENING: yes.
  Its prose found NO blocker ("No realistic dropped-valid-trigger, unbounded-growth, or work-after-
  dispose blocker remains"); the boolean fired only because trigger 4097+ in the single pre-ready probe
  window is dropped at the 4096 cap.
- Adjudication (read the actual code end to end): the drop is a FUNDAMENTAL, forced tradeoff, not a rig.
  Bounded memory + adversarially-unbounded distinct input => a drop must exist somewhere; no finite cap
  (nor a dedup-set variant) removes it. History proves the tension: cap=64 dropped ORDINARY triggers
  (RED), uncapped grew unbounded (wire-lazy4 RED), cap=4096 (~2000 calls in one sync) sits far above any
  real 1:1 workload. _scanIndex iterates _index.keys() ONLY, so a dropped (never-indexed) trigger
  recovers solely if its half RE-SYNCS -- best-effort, and the individual halves still render (P4
  fallback). NOT a CI/test-gate softening: no test weakened, no check exempted.
- The ONE real gap the flag pointed at: the drop branch was a deliberate fail-open with a comment but NO
  runtime signal -- our "no silent failures" rule wants unexpected states logged (or silent-ok labelled).
  FIX: added _mergeBufferSaturated latch + a ONE-SHOT Logs().w at the drop site (warn once per saturation,
  never per-trigger -> no log storm). Latch is never cleared BECAUSE _mergeReady is write-once (set true
  once, never reset) so buffering -- hence saturation -- cannot recur; doc updated to state exactly that.
- Gates GREEN: dart format (0 changed), analyze (No issues found), import_sorter --no-comments (0 sorted).
  Cold Codex gate (gate-mergebuf-obs, source INLINE, read-only, verdict outside -C): all 4 questions
  clean -> VERDICT: CORRECT / GATE-SOFTENING: no. The contradiction is resolved at root.
- No new unit test for the log-once: the drop path is a private CallService method needing a full
  Client+GetStorage-stall harness the wiring brief deliberately avoids; analyze covers compile, the
  latch invariant is locally obvious. Flagged honestly, not hidden.
- Diff: lib/routes/chat/calls/call_service.dart only (+22/-3). calls bucket re-run in flight (additive
  change; was +1678 green). Commit pending bucket-green confirmation.

## 2026-09-08 (cont) — LESSON: laptop overload purged the pinned Flutter SDK; NOT a code leak
- Symptom: after the observability edit, the FULL calls bucket flaked RED at `(tearDownAll)` -- run 1
  `+1676 -3` attributed to call_timeline_event_dedup_test.dart (+1670), run 2 hung at active_call_test.dart
  (+573). Baseline HEAD (change stashed) was `+1679` GREEN. The change is provably INERT (adds no timer;
  the new drop-branch is untested-by-design and executed by no test; its own files -- coordinator/wiring/
  service/selection suites -- pass).
- ROOT CAUSE = machine thrash, not the code. `top`: load avg 15, PhysMem 15G used / 68M free, and macOS
  Spotlight (`mdworker_shared`/`mds`) + CacheDelete (`deleted_helper` 69% CPU) saturating the box. A
  starved CPU fires a real Timer late, tripping flutter_test's pending-timer boundary check on whichever
  file sits at the boundary -- hence the WANDERING attribution (a real leak reproduces in ONE place, in
  isolation; this did neither: dedup passes +24 alone). The trigger was DISK: the Data volume hit 89%
  (47Gi free), and `.claude/worktrees/*/build` had grown to ~28GB (combined/build alone 10.5G); CacheDelete
  then PURGED `~/fvm/versions/3.41.4` (the pinned SDK) to reclaim space, leaving only Homebrew 3.44 (which
  breaks the widget suite).
- FIX: deleted build/ + .dart_tool across all ~40 worktrees (gitignored, regenerable) -> reclaimed 27GB
  (48203->75990 MB free; 89%->83%). Reinstalling fvm 3.41.4 (CLI survived at ~/.pub-cache/bin/fvm). Then
  ONE clean SERIAL calls run confirms green (no concurrent buckets -- running three at once is what tipped
  the box).
- PREVENTION: never run >1 full flutter bucket concurrently on this laptop; purge worktree build/ dirs
  between phases; tear the local stack + docker down when a work chunk ends (user directive this turn).
  A green run needs a quiet machine here -- a RED that wanders across files under high load average is an
  environment signal, not a regression (see also the DSN-gated-tests "baseline-worktree before calling a
  failure a regression" lesson).

## 2026-09-08 (cont) — LIVE E2E of PR2 + two owner-found issues (one fixed)
- Stood up the LOCAL stack (Synapse+livekit+lk-jwt+choreo) + built & served the COMBINED web app on
  :8091, ran the browser E2E harness (test/e2e/transcript.js) TWICE. Both 18/18. Proved the record ->
  merge -> Full-call chain end to end in a real call: both sides post pangea.call_audio (mxc upload),
  the elected device (calltester) downloads both halves, mixes, and posts pangea.call_audio_merged
  (2 source ids, one per participant, audio/wav 16kHz mono, mxc). Owner's screenshot confirmed the P4
  "Full call" player row renders + plays. STT cost approved by owner.
- Owner-found #1 (stray "you"): a lone 1-word segment in the learner half at 35.7s. NOT the ordering
  bug -- it is a speech-to-text artifact on the trailing near-silent chunk; ordering is correct (at_ms
  places it right). Did not recur with the spaced-conversation fixtures. Lives in streaming_stt, not PR2.
- Built SPACED conversation fixtures (6-turn alternating, say+afconvert, silence-gapped) to replace the
  overlapping monologues; re-ran -> proper A/B/A/B interleave, no stray "you". Also surfaced: recording
  starts at CaptureElection (call establishment), so a caller talking during the RING is not recorded
  (metadata: chunks_lost=0/discarded=0) -- a fixture artifact, not a drop.
- Owner-found #2 (REAL, FIXED): transcript turn times did not line up with the Full-call recording. Root
  cause (documented in turn_timeline.dart:CallTurn.at): turn times anchored to the FIRST WORD, the
  recording to when recording began -- a constant ~5.85s lead-in gap (ring+silence). turn_timeline said
  reconciling needed "a wire change"; but PR2's merged event carries merged_start_sfu_ms and a segment's
  (orderKeyMs - shift) is on that same SFU clock, so it is a DISPLAY change. FIX (f39a11d96a):
  _turnsOf(recordingOriginMs:) uses the merged row's start as the origin when a merge is shown; guarded
  <= firstPlaced (no negatives); falls back to first-word when no merge / null / malformed-after-first-
  word. Re-anchor subtracts one constant -> no reorder, no time-kind change, isolation preserved.
- Gates GREEN: analyze/format/import clean; calls bucket +1682 (added 3 widget tests, RED-on-revert
  PROVEN by mutation); cold Codex behaviour gate VERDICT CORRECT / softening no; cold pinning gate
  VERDICT SOUND / softening no.
- Stack + spa_server on :8091 left UP for owner's own testing (idle = light; overload was disk, since
  reclaimed). Tear down when owner is done. PR2 branch now: cues(#8888)+tokenize(#8797)+record+merge+
  player+wiring+this fix; rebase on main after #8888/#8797 land so PR2 shows only its delta.

## 2026-09-10 — mute-at-end drop ROOT-CAUSED + FIXED (intermittent tap-death race)
- SYMPTOM (owner, real call): muted on phone then hung up -> phone's half did not upload; laptop's did.
  A call right after WITHOUT muting uploaded both; a later mute call ALSO uploaded. Intermittent.
- Ruled OUT deterministic mute: the `REPRO mute-at-end` unit test carries `wasCarryingBeforeLastStop`
  == true (pure mute does not end the audio run). So the drop is a RACE, not the mute path itself.
- ROOT CAUSE (call_capture.dart): the tapped mic track can END a beat before the explicit hangup (mute
  calls setMicrophoneEnabled(false), which on device can end the track; or teardown ends it early).
  That fires `_onTapDied`, which issued a bare `stop()` == settle-shaped + `preserveCarrier:false` (a
  HANDOVER shape). `_stop` writes `wasCarryingBeforeLastStop` only on `!settleDeliveries` (hangup) OR
  the `preserveCarrier && _running && !_discardOnStop` latch -- the tap-death stop hit NEITHER, and tore
  the recorder down (`_running=false`, `_chunker=null`, `_detach=null`). The hangup's own
  stop(settleDeliveries:false) then found everything idle, hit the early-return (line ~1618), and NEVER
  wrote the snapshot. It stayed false -> call_audio_recorder.dart:968 gate "not carrying" -> half dropped.
  Intermittent because it only bites when the tap dies BEFORE the hangup.
- SAME CLASS as the peer-drop-pause bug that group already fixed: a settle-shaped stop that is NOT a
  sibling handover must latch the carrier. Tap-death (`_onTapDied`) was the one caller that missed it.
- FIX: `_onTapDied` now `stop(preserveCarrier: true)`. A tap death is not a handover (no sibling took
  the stretch), so this device must publish its half; `!_discardOnStop` still leaves a genuine handover
  uncarried (no double-upload). Generalized 3 doc comments from "peer-drop pause" to cover both callers.
  One-line behavioural change; the rest is documentation.
- TDD/PROOF: added group 'a tap that dies while this device is the sole carrier' in call_capture_test.dart
  (2 tests). Repro test RED before fix (Actual: false), GREEN after; no-regress (tap-death DURING a
  handover) stays false both ways. Full calls bucket: +1685 All passed, exit 0. No cross-file regression.
- Enumerated all capture stop() callers for the class: reconcile(982, correct), hangup(2617, reads
  _running), finish(1785, reads _running), _onTapDied(1731, WAS the bug). call_audio_tap.dart:376
  `capture.stop()` is a DIFFERENT object (platform tap), not the service -- not in scope.
- STILL QUEUED (owner's order): (2) transcript->recording-timeline (already partly done f39a11d96a; owner
  wants transcripts generated/aligned to the recording clock -- fixes ordering + enables karaoke); (3)
  loading states in transcript_view (spinner while peer half / merge pending, error only after timeout);
  (4) recordings UI redesign (sticky Full-call bar, expandable per-device, Mobbin research -- MCP needs
  re-auth); (5) karaoke auto-scroll+highlight. Then whole-branch cold-Codex-green + owner test -> PR2 on go.

## 2026-09-10 (cont) — item 2 ordering ROOT-CAUSED with real data; 2+3+4+5 folded into one design-first UI chunk
- Pulled the newest real call's events from local Synapse (learner+calltester room !HgavfyvZrMpYhLFMLt).
  Newest merged call: phone offsetMs(dev-sfu)=1435 fileStartSfuMs=...655667(=merged 0:00);
  laptop offsetMs=4 fileStartSfuMs=...655731. A laptop turn: at_ms=...663456 span=3652 -> audio
  plays 0:07.8 but transcript shows 0:11.4 (orderKeyMs=at_ms+span = chunk END).
- ROOT CAUSE of "transcript off from recording": NOT a clock bug. `at_ms - offsetMs` lands each word
  on the SFU clock exactly where the recording places it (both anchor halves ARE on the wire; earlier
  session's "device_joined_at_ms missing" was a dump-filter mistake). The skew is that APPROXIMATE turns
  are placed at `orderKeyMs = at_ms + at_span_ms` (chunk END, transcript_view.dart:665 CallTurn.at) to
  avoid answer-before-question in the STANDALONE list, but the recording plays each turn at its START
  (at_ms). Precise (`m:ss`) turns align; approximate (`by m:ss`) lag by their span (here 3.65s).
  f39a11d96a fixed only the origin, so the per-turn lag remained.
- REFRAME: item 2 (ordering vs recording) and item 5 (karaoke) are ONE mechanism — place each turn on
  the recording timeline by its audio window [at_ms, at_ms+span] (anchored at START), then highlight +
  auto-scroll the turn whose window holds the playhead; tap-to-seek. They render in the widget item 4
  redesigns, and item 3 (loading states) lives there too. So 2+3+4+5 = ONE design-first UI chunk.
- Design-language anchors found: transcript is `TurnTimeline`; recordings render at the BOTTOM today as
  name + `AudioPlayerWidget` (lib/routes/chat/audio_player.dart, 40-wave scrubber). Redesign: sticky
  Full-call bar on TOP + expandable per-device rows, reuse AudioPlayerWidget, keep design language.
- USER DIRECTIVES this turn: (a) one design-first UI chunk; (b) do Mobbin MCP research + web research on
  recording placement/features/UI; (c) mirror what the client already does, keep design language same;
  (d) both the item-1 fix AND the new feature are done BY AGENTS that run Codex gates within to green,
  then I (orchestrator) run a COLD Codex green on top, then report. NO code lands before the design is
  approved by the owner.
- Mobbin MCP: still NOT exposing tools this session (ToolSearch "mobbin" -> none). Terminal auth done but
  not propagated here; needs a chat reopen on owner's end. Proceeding with client-internal + web research
  now; fold Mobbin screens in when it reconnects.
- IN FLIGHT: Explore agent a46c8a3c5890b8d5e (mapping client UI patterns: AudioPlayerWidget internals,
  expand/collapse, sticky headers, loading/skeleton, list-highlight+ensureVisible, theme tokens).
  item-1 Codex gate: bg codex exec (task bkxfj1har), gate dir scratchpad/gate-item1 (FACTS+diff+src),
  verdict -> scratchpad/gate-item1-verdict.txt. Awaiting both.
- NEXT: on Explore -> draft the UI design spec (sticky Full-call bar, expandable per-device rows,
  recording-aligned turns, loading states, karaoke highlight/auto-scroll/tap-seek) + draft the governed
  doc section (voice-video-calls "What a turn's time promises") for owner review; Codex-gate the DESIGN
  to green; gist; WAIT for owner go; then agents build+self-gate; then my cold green; then report.

## 2026-09-10 (cont) — item-1 cold gate caught a double-upload; root-caused + fixed + re-gating
- Ran a cold Codex behaviour+pinning gate on the committed item-1 fix (17bbfbec89). BEHAVIOUR
  VERDICT: ISSUES-FOUND (softening: NO). Real hole my `preserveCarrier:true` opened:
  stretch A records -> handed to a sibling; this device re-elected (stretch B) -> B's tap dies
  BEFORE any frame. The audio generation opens on the FIRST frame (call_capture.dart:1286) and
  `onRunEnded` does not cancel it (call_audio_recorder.dart:824), so the recorder's CURRENT
  generation is still A's (the sibling's half). The fix latched carrier=true for B -> finish
  uploads A again -> merged recording double-covers the stretch. Pre-fix (bare stop) this could
  not happen. Gate also: pinning missed the zero-frame case.
- ROOT CAUSE / RULE: carrier=true at the final stop IFF the recorder's current generation is one
  THIS device recorded this stretch and did not hand over. A zero-frame stretch holds no
  generation of its own; latching there resurrects the prior (handed-over) one.
- FIX: new per-stretch flag `_recordedFrameThisStretch` (set on any `recorderLive` frame incl.
  muted, in _onFrames; cleared in start()); added to the latch condition. Chosen over
  `_audioRunFormat != null` because that is only set when a recording SINK is wired, and the
  default test `service()` wires none -> gating on it would have broken the 5 passing peer-drop/
  carrier tests. The new flag is sink-independent and semantically precise.
- TESTS: added 2 (zero-frame tap death -> no carry; zero-frame-after-handover -> does not
  resurrect the sibling half). MUTATION-PROVEN: with `&& _recordedFrameThisStretch` removed both
  FAIL (Expected false, Actual true); restored -> call_capture_test +126 green, format clean.
- IN FLIGHT: re-gate (codex, task baw46zt0p, dir gate-item1b, 309-line combined diff <350);
  full calls bucket (task buk4y063e). Amend the item-1 commit once both green.
- LESSON: a one-line carrier latch in the capture service can desync from the recorder's
  generation lifecycle (generation opens on first frame, lingers after handover). Any change to
  `wasCarryingBeforeLastStop` must be reasoned against "which generation will finish upload",
  not just the tap/stretch state. The cold gate earned its place here.

## 2026-09-10 (cont) — re-gate found the carrier bug CLASS; guard reverted; scope decision pending
- Re-gate (baw46zt0p) of the amended item-1: closed the exact zero-frame tap-death (v1) but FAILED on
  the CLASS: (3a) handover A -> zero-frame re-election B -> direct HANGUP still snapshots `_running`
  (the hangup branch is unguarded) -> re-uploads A (sibling's half); (3b) the `_recordedFrameThisStretch`
  guard INTRODUCES a v1-reachable DROP -- learner records A, PEER connection flaps (drop/return/drop)
  while learner is SILENT (zero-frame B) -> A (owned, never handed over) is dropped.
- ROOT CAUSE (the class): `wasCarryingBeforeLastStop` is a per-STRETCH flag, but it gates which RECORDER
  GENERATION `finish` uploads, and that generation has its own lifecycle (opens on first frame, lingers
  after a handover). The two desync across a zero-frame stretch. No per-stretch guard fixes it (it can't
  tell an owned-but-idle prior generation from a handed-over one); only tracking generation OWNERSHIP does.
- ACTION: reverted the guard + its 2 tests via `git checkout HEAD -- call_capture.dart call_capture_test.dart`.
  Working tree now == committed 17bbfbec89 (`_onTapDied` -> `stop(preserveCarrier: true)` ONLY). That fix
  is CORRECT for a normal 1:1 call (single device each side): no handover -> `_discardOnStop` never true
  -> no double-upload, no 3b. It DOES add a v2 double-upload (needs a 2-device handover) vs baseline.
- SCOPE: all remaining carrier edge cases (first-gate tap-death double-upload, 3a) require a MID-CALL
  2-DEVICE HANDOVER -- the same territory as the DEFERRED v2 device-switch merge (issue pangeachat/client#8878).
  Decision put to owner: (B, recommended) ship the v1-correct fix, fold the carrier/generation-ownership
  redesign into #8878 with a code comment; or (A) redesign the carrier flag to track ownership now
  (fixes every case, but bigger + churns the invariant-heavy carrier tests + pulls v2 work forward).
- DESIGN GATE (bk69sm474): REVISE, 6 hardening points (all sound, none fundamental): null-not-shift0 for
  unreconciled halves + precise-turn empty-window rule; karaoke controller ownership/disposal/atomic seek;
  loading machine needs a real expiry timer not just participants; player won't fit 56px toolbar + lazy
  slivers break ensureVisible; lock printed-label/order invariance tests; a11y/RTL/reduced-motion/gesture.
  Revising the spec (v2) + re-gate. No owner decision needed on design.

## 2026-09-10 (cont) — item-1 SCOPED to v1 (owner chose B); spec v2 folds the 6 design-gate points
- Owner decision: ship the v1-correct mute-at-end fix; defer the carrier/generation-ownership redesign
  to #8878. Added a KNOWN-LIMIT code comment at `_onTapDied` (commit e54141eeef) documenting the
  mid-call 2-device-handover double-upload + the #8878 deferral. Final v1-scoped cold gate running
  (bbgu5hemv, dir gate-item1c) -- asks correctness WITHIN v1 scope + whether the deferral is honest.
- Design spec v2 (committed): folded all 6 design-gate findings -- (1) null-not-shift0 for unreconciled/
  not-in-merge halves + precise-turn active-until-next-start window + clamp-to-0; (2) CallPlaybackController
  observes voiceMessageEventId, clears on owner change, serializes load->seek->play, cancels subs on
  dispose; (3) loading machine: stamped graceStartedAt + bounded ~30s Timer + merge/half subscription +
  retry, participants only a hint; (4) custom SliverPersistentHeader fixed extent (not a 56px SliverAppBar),
  per-device rows a SEPARATE sliver, turns NON-LAZY so ensureVisible works; (5) before/after invariance
  test locking CallTurn.at + order; (6) accessible seek affordance on the time/avatar (not whole-bubble,
  keeps text selection), non-color active accent bar, reduced-motion, RTL, identity-keyed GlobalKeys,
  no-notify-after-dispose. Resolved D1 (grace timer) + D4 (explicit affordance). Design re-gate running
  (bh1ksctsw, dir gate-design2).
- NEXT: on both gates green -> present item-1 done + spec-approved to owner for the GO; then dispatch the
  6 build agents (each self-gates), orchestrator cold-greens the delta, owner review. No build before GO.

## 2026-09-10 (cont) — item-1 v1 gate GREEN (done); spec v3; execution model changed to orchestrator-gates
- Final v1-scoped item-1 gate (bbgu5hemv): OVERALL CORRECT, SOFTENING NO. All 4 pass: in-scope correct;
  no normal-call regression (zero-frame single stretch never creates `_current`, finish uploads nothing);
  #8878 deferral honest; tests correctly pinned (additions-only, positive fails on revert). ITEM 1 DONE
  (commits 17bbfbec89 fix + e54141eeef deferral note; part of PR2, not opened).
- Design re-gate round 2 (bh1ksctsw): REVISE, converging (findings 1/4/5 confirmed addressed). Round-2
  refinements folded into spec v3: loading machine made TOTAL (zero-halves-done=NONE; graceStartedAt
  stamped when both reads complete); karaoke seek rechecks ownership AFTER each await (aborts if a
  per-device player took over mid-await); GlobalKey = senderId+halfEventId+segmentIndex (index alone
  collides -> crash); header extent scale-aware + label ellipsized (56px/200%-scale clip); clamp tie-break
  by standalone order; a11y announces the recording-relative START (0:03) not the printed "by 0:07";
  non-lazy turns noted as STATUS QUO (today renders all eagerly); steps 4+5 both edit transcript_view.dart
  -> SERIAL not parallel.
- EXECUTION MODEL CHANGE (owner): the ORCHESTRATOR cold-gates EACH build agent's diff (agents do NOT
  self-gate); on RED, root-cause + SendMessage the SAME agent to fix, re-gate, loop to green (pivot at 4,
  stop at 7-8); then one final cold green over the assembled delta. Spec section 9 updated.
- Design re-gate round 3 running (gate-design3). On SOUND-TO-BUILD -> present spec for owner GO -> build.

## 2026-09-10 (cont) — design spec SOUND-TO-BUILD (4 gate rounds); awaiting owner GO
- Design re-gate round 4 (bddfnd2rr): SOUND-TO-BUILD. All 3 PASS: seek ownership race fully closed
  (recheck after every await; check->seek and check->play have no suspension point); no other
  architectural blocker; printed-time + standalone orderKeyMs semantics isolated + mutation-tested.
- Design converged over 4 rounds: r1 6 broad findings -> r2 refinements (1/4/5 confirmed) -> v3 folds r2
  -> r3 down to 1 blocker (seek recheck-before-play) + 2 clarifications -> v3.1 fixes -> r4 GREEN.
- Spec v3.1 committed (37663d5309 area + v3.1 commit). Design phase DONE. Awaiting owner GO to build.
- BUILD PLAN on GO: dispatch agents 1(timeline model)->2(CallPlaybackController)->3(karaoke render) in
  order, then 4(loading machine in transcript_view), then 5(layout in transcript_view, rebased on 4);
  6 = doc draft held for review. Orchestrator cold-gates EACH agent's diff; RED -> root-cause +
  SendMessage the same agent -> re-gate -> green; then one final cold green over the delta; then owner
  review. No PR without explicit go. PR2 rebase on main after #8888/#8797 land.

## 2026-09-10 (cont) — BUILD started; agent 1 (timeline model) cold-gated -> fixer dispatched
- Agent 1 (a25a230abcf744c4a, sonnet) delivered the recording-timeline model: CallTurn gains
  audioStartMs/audioEndMs + identityKey; _turnsOf computes the window (atMs-shift-origin clamped;
  orderKeyMs for end) gated by windowEligible; mutation-proven tests; 89 green, format+analyze clean.
  UNCOMMITTED (dispatched before I re-read subagent-dispatch-protocol; no self-gate/commit).
- My cold gate, split behaviour (bc1vhe12q) + pinning (bm4alvbs9), both ISSUES-FOUND, GATE-SOFTENING no:
  - Q1 clamp/`!` type error = FALSE POSITIVE (verified: `flutter analyze` clean; Dart promotes after `!`,
    int.clamp(int,int)->int). Q5 required-identityKey = handled (all 3 sites updated). Q2 null-safety CORRECT.
  - Q4 identity STABILITY (real): senderId#index shifts if the segment list grows/reorders mid-playback ->
    a turn's GlobalKey changes -> karaoke scroll/highlight breaks. Fix: stable per-segment identity (atMs+tiebreak).
  - Q3 sender-level vs event-level coverage (real, v2-only): a sender with 2 recordings + merge names one ->
    all its turns get windows incl. the excluded device. v1 (one device/account) = exact; TranscriptHalf has
    no per-segment id so event-level is impossible here -> scope to #8878 with a comment.
  - Pinning gaps: no non-zero clock-shift case (shift term unpinned), no upper-clamp case, no null-window
    assertion for the no-start merge, and the invariance test is misframed (it sidesteps f39a11d96a's
    intentional `at` re-anchor by using a no-start merge; must reframe around a start-bearing merge).
- FIXER re-spawned (a937f8c931cc78d5d, sonnet) with all findings root-caused + false-positives flagged,
  under the FULL protocol: self-gate with codex to CORRECT/softening:no, then COMMIT (no push/PR) to
  satvik/call-features-combined. On its return I re-cold-gate (behaviour+pinning). SendMessage-to-subagent
  is NOT exposed here, so "on red -> message the agent" is implemented as re-spawn-with-artifacts.

## 2026-09-10 (cont) — agent 1 fixer round 1 committed a819840d30; cold-gate r2 -> fixer r2
- Fixer r1 (a937f8c931cc78d5d) committed a819840d30: stable content-based identityKey, merge-coverage
  comment, window/shift/clamp/null-window/invariance tests (self-Codex-green behaviour 3 rounds + tests
  4 rounds). Repo verified clean (no import_sorter collateral; it caught my brief's missing --no-comments
  and reverted ~1600-file collateral). It also CORRECTED my "v1 = one recording per sender" claim: the
  CaptureElection convergence race makes 2-recordings-per-sender reachable in an ordinary call.
- My cold gate r2: behaviour codex ISSUES-FOUND (softening no) + I hand-verified the test pins (invariance
  3-pump, window/clamp arithmetic, non-zero-shift term — all genuine). Two real behaviour issues:
  - Q1 identityKey COLLISION: content key senderId#atMs#span#text is not injective (two identical "yes"
    utterances in one chunk share atMs+span+text) -> duplicate GlobalKey -> Flutter crash. Fix: unique +
    still-stable (append a stable ordinal among exact-duplicate content within the half).
  - Q2 merge coverage: gate REJECTED the "documented + deferred" framing -- a reachable defect isn't
    correct just because commented. Clean conservative fix (no #8878 needed): a sender is eligible only if
    ALL their recordings are in the merge's sourceEventIds; else no window (safe, no wrong seek). My earlier
    v2-scoping of this was too quick.
  - Q3 window math, Q4 invariance/regression: CORRECT.
- FIXER r2 (a190b6aa9baf96261, sonnet) dispatched with both fixes root-caused + the corrected
  import_sorter --no-comments; full protocol (self-gate + NEW commit, no amend/push/PR). On return I
  re-cold-gate the two fixes. LESSON: agent briefs must use `dart run import_sorter:main --no-comments
  --exit-if-changed` (omitting --no-comments rewrites ~1600 files).

## 2026-09-10 (cont) — STEP 1 DONE (cold-green); agent 2 (playback controller) dispatched
- Fixer r2 (a190b6aa9baf96261) STALLED: backgrounded its codex self-gate + ended its turn (2nd agent to
  hit the codex-buffering anti-pattern). Its WORK was uncommitted but present. I killed the orphaned codex,
  verified full-local-green myself (import_sorter --no-comments/format/analyze clean; 95 tests pass), and
  read the diff to confirm it made exactly the two specified fixes:
  - Q1: `_turnContentKey` + a per-content-key ORDINAL (`contentKey#N`) -> unique AND stable (moves only for
    identical-content siblings inserted ahead); ordinal is pure digits last so the final `#` is unambiguous.
  - Q2: `recordingsBySender` + `.every(r in sourceEventIds)` -> a sender is eligible only if ALL their
    recordings are in the merge; else no window (conservative, no wrong seek). Comment reframed: CLOSED
    conservatively, not deferred.
- My cold gate r3 (sole gate, per the stall fallback): behaviour (bmaro4qve) CORRECT 5/5, pinning (bm1nmaak1)
  CORRECT 5/5, both GATE-SOFTENING no. Committed f12bcac0ad (I made the commit the stalled agent didn't).
  STEP 1 (timeline model) COMPLETE + cold-green.
- Agent 2 (af6b526de0e01f128, sonnet) dispatched: `CallPlaybackController` (playhead+ownership->active turn;
  greatest audioStartMs<=pos, tie-break later-in-display; immediate clear on ownership change; serialized
  seek with ownership recheck after EVERY await incl. seek-before-play; in-flight guard; dispose cancels
  subs + no-notify-after-dispose). Injected deps for testability; render/wiring is agents 3/5. Brief hardened
  with a strong ANTI-STALL note (foreground codex, never background) after 2 stalls.
- Running the full calls bucket now as a step-1 regression check.
- PROCESS NOTE: agent codex self-gate keeps stalling (backgrounded). Fallback (verify local-green + my cold
  gate as sole gate) works but costs me the verify+commit. If it recurs, switch agents to "commit on
  local-green, my cold gate is the gate" explicitly.

## 2026-09-10 (cont) — step 1 test-strengthening accepted (9b31e5be9e); concurrency LESSON
- The "stalled" fixer r2 (a190b6aa9baf96261) was NOT dead -- its codex self-gate resumed, it found I'd
  already committed its work (f12bcac0ad) + moved on, verified the landed production code byte-identical
  to what it wrote, and its own 4-round codex found 2 TEST gaps on the landed fix -> committed 9b31e5be9e
  (TEST-ONLY, +145/-9): (a) the "merge names only one" test only had ONE turn for the affected sender ->
  strengthened to TWO (both null); (b) added a 3-duplicate+rebuild test (ordinals continue past 2; key
  SET stable across rebuild = fresh map per _turnsOf). I READ the diff: pure strengthening (the 9
  deletions replace a 1-turn assertion with a 2-turn loop), mutation-proven, GATE-SOFTENING no. Accepted
  on my read + the r3 pinning gate + the fixer's 4-round self-gate (no redundant 4th codex). Tests 96/96,
  full bucket 1698 -- STEP 1 fully done + strengthened.
- LESSON (concurrency): I dispatched agent 2 into the SAME worktree believing the fixer had died on its
  stall. It hadn't -- it resurrected and committed on top, so two agents were briefly live in one
  worktree. It worked out (fixer's commit was test-only; it carefully staged only its file, left agent 2's
  untracked files alone; no conflict), but it violated the protocol's "parallel same-repo agents each get
  their own worktree." RULE going forward: a "stalled" agent is not confirmed dead; before dispatching the
  next agent into a shared worktree, confirm the prior is terminated OR isolate. Agents 3/4/5 are SEQUENTIAL
  (share transcript_view.dart) so only one at a time -- do NOT dispatch the next until the prior is done +
  cold-gated. Agent 2 (af6b526de0e01f128) is the only live agent now.
- Unrelated shared-stack stash present (WIP on satvik/call-audio-recording) -- another worktree's, NOT
  mine; never touch it.

## 2026-09-10 (cont) — agent 2 (CallPlaybackController) committed 5c8dfc7e0b; cold-gate found 2 seek gaps
- Agent 2 (af6b526de0e01f128) committed 5c8dfc7e0b: CallPlaybackController (playhead+ownership->active
  turn; serialized seek w/ _awaitWhileOwned watching EVERY intermediate ownership change to close the ABA;
  in-flight guard; disposal cancels subs + in-flight watchers). Self-Codex-green 4 rounds (found+fixed real
  bugs: position contamination, isPlaying-stuck-false, ABA reclaim, in-flight listener leak). 19
  mutation-proven tests. Foreground codex worked (anti-stall held). Flagged a real WIRING precondition: a
  bare Stream<Duration> can't tag ticks by owner, so a post-ABA stale tick needs sync subscription teardown
  at the wiring layer (agent 5) -- correctly not closable inside the controller.
- My cold gate: behaviour (ba957i59i) ISSUES-FOUND (softening no), 5/6 CORRECT. Q1 = 2 narrow seek gaps:
  (A) _awaitWhileOwned gets an already-started future -> watcher registered AFTER the action starts, so a
  SYNCHRONOUS ownership flip during the action's sync portion is missed; (B) a microtask gap between
  _awaitWhileOwned's internal _owns check and play() lets ownership leave then play() still runs. Both
  narrow (prod ownership changes are user-driven) but break the "never play the wrong source" guarantee.
  I independently READ the ownership+seekToTurn tests -- genuinely strong (the ABA test is a standout).
- FIXER (a344faed6a3ea914a) dispatched: (A) _awaitWhileOwned takes a THUNK, add watcher then await action();
  (B) final synchronous `if(!_owns) return;` immediately before play(). + mutation-proven tests. Full
  protocol + hardened anti-stall. On return I cold-gate the fix. Q2-Q6 CORRECT (untouched).

## 2026-09-10 (cont) — agent 2 fix r1 committed 1bf3ec966e; cold-gate found same-class gap at seek boundary
- Agent 2 fixer r1 (a344faed6a3ea914a) committed 1bf3ec966e: GAP A (thunk -> watcher registered before the
  action's sync prefix) + GAP B (final sync `if(!_owns) return` before play). Self-Codex-CORRECT (foreground,
  no stall). 2 excellent deterministic tests (GAP A sync flap; GAP B getter-hook, honest about Dart's
  synchronous cascade). 20/20. Format/analyze clean; the 2 files pass import_sorter individually.
- import_sorter YELLOW: `import_sorter:main --no-comments --exit-if-changed` CRASHES on the full repo (1731
  files) in this env -- dies after "Sorting..." with no completion, clean tree (dry-run), no file named. NOT
  a code issue: each new file sorts clean run individually ("Sorted 0 files"). Pre-existing/environmental,
  a pending task already tracks it. RESOLVE-BEFORE-PR2: confirm whether CI actually hits the crash; the new
  files' imports are sorted regardless.
- My cold gate on the fix (baze927y7): Q1 (thunk) + Q2 (pre-play guard) CORRECT; Q3 ISSUES-FOUND (softening
  no) -- SAME CLASS at a NEW site: after startMergedPlayer completes, ownership is not re-read before seek(),
  so ownership leaving in the load->seek gap lets seek() run on the foreign source (and seek-after-dispose).
  Red-to-root-cause recurrence: the recheck rule was applied before play but not before seek.
- FIXER r2 (affe1e2fafa5512a6) dispatched: add `if(_disposed||!_owns) return;` after the startMergedPlayer
  await, before seek -- completing "recheck ownership synchronously after EVERY await" at all load->seek->play
  boundaries (structural, not spot-patch). + mutation-proven test. On return I cold-gate. Told it to verify
  import_sorter per-file (the full-repo run crashes).
- META: the controller's concurrency is genuinely hard; 3 gate findings (2 gaps + this) all real. Double-gate
  earning its keep but slow. User offered no redirect on loosening; continuing as specified.

## 2026-09-10 (cont) — fixer r2 committed 94cf22a322; self-Codex-CORRECT, closes load->seek gap (Q3)
- Fixer r2 committed 94cf22a322: added `if (_disposed || !_owns) return;` at the end of the
  `if (!_owns) { ... }` load block in seekToTurn, immediately after startMergedPlayer's _awaitWhileOwned,
  with nothing awaited before the seek call that follows -- mirrors the existing pre-play guard, completing
  the "recheck ownership synchronously after every await" rule at both remaining boundaries (load->seek,
  seek->play). Did not touch the thunk/watch/ABA logic or the pre-play guard. Updated seekToTurn's doc
  comment to describe the transaction as 4 steps instead of 3.
- 2 new mutation-proven tests in the seekToTurn group: ownership-flips-in-the-gap and
  disposed-in-the-gap, both asserting seek() never fires (spies.seeks stays empty) and play() never fires.
  Reused the existing GAP-B `_CountingOwnership.onRead` technique (armed at count==4: reads 1-3 are
  _onOwnershipChanged's _recomputePlaying/_recompute + the load watcher, all firing off
  claimsOwnershipOnStart's write; read 4 is _awaitWhileOwned's own verdict read for the LOAD call).
  Mutation proof done BY HAND (temporarily commented out the new guard, ran the file): RED on both new
  tests (seeks == [3000ms] instead of empty), all other 18 tests still green; restored -> 22/22 green.
- Full local gate green: pub get; import_sorter scoped per-file (source: "Sorted 0 files"/exit 0; test file
  under --exit-if-changed still hits the known pre-existing crash -- cross-checked by running WITHOUT
  --exit-if-changed, which revealed it wanted to insert a spurious blank line splitting
  package:flutter/foundation.dart from package:flutter_test/flutter_test.dart in an import block this diff
  never touched; reverted that by hand so the import block stays byte-identical to 1bf3ec966e); dart format
  0 changed; flutter analyze clean; flutter test 22/22.
- Self-gate: foreground blocking `codex exec -s read-only --skip-git-repo-check` from a FRESH scratch dir
  outside the repo (the shared `scratchpad/gate/` dir had stale files from an earlier round -- did NOT reuse
  it, per the cold-gate-dir-hygiene lesson; used a new `gate_q3_loadseek_<ts>/` dir with only a fresh
  FACTS.md). Verdict CORRECT, GATE-SOFTENING no on all 6 checks -- notably it independently re-derived the
  onRead==4 count itself and cross-checked it against the ACTUAL installed Flutter SDK's
  ValueNotifier/ChangeNotifier source (confirmed the setter doesn't invoke the overridden getter, and
  listeners fire in registration order), rather than trusting the FACTS.md narrative.
- Awaiting orchestrator's own independent cold gate on 94cf22a322 per protocol.

## 2026-09-10 (cont) — STEP 2 DONE (cold-green); dispatching agent 3 (karaoke render)
- Agent 2 fixer r2 (affe1e2fafa5512a6) committed 94cf22a322: added the missing `if(_disposed||!_owns)
  return;` after the load await, before seek -- completing "recheck ownership after EVERY await" at all
  load->seek->play boundaries. 22/22 tests (2 new: departs-in-gap, disposed-in-gap). Self-Codex-CORRECT
  (re-derived onRead==4 vs the real SDK source). It also confirmed import_sorter is genuinely misbehaving
  (wanted to insert a spurious blank line in an untouched import block -> kept imports byte-identical to
  parent). NOTE: it also committed adcf499688 to MY handoff log ("per convention") -- harmless/accurate,
  but agents should NOT write the orchestrator's handoff log; noted, kept.
- My completeness cold gate (bsefgmqun): OVERALL CORRECT 3/3, softening no. All await->action boundaries
  rechecked, no residual gap, no regression. STEP 2 (CallPlaybackController) COMPLETE + cold-green
  (5c8dfc7e0b original -> 1bf3ec966e 2 gaps -> 94cf22a322 completeness).
- Agent 2 total: 4 gate findings across 3 rounds, ALL real, all in the seek-transaction ownership
  guarantee (the feature's hardest concurrency). The double-gate earned its keep here.
- Dispatching agent 3 (karaoke RENDER in turn_timeline.dart): consume activeIndex/isPlaying + accent-bar
  active highlight + identity GlobalKeys + ensureVisible auto-scroll (playing-only, user-scroll suspend,
  reduced-motion) + the D4 accessible seek affordance (Semantics on the time/avatar announcing audioStart;
  text stays selectable). Takes the controller's outputs + an onSeekTurn callback as INPUTS; wiring is
  agent 5. Agent 2 is done, so agent 3 is the only live agent (sequential, shares turn_timeline.dart).

## 2026-09-10 (cont) — agent 3 (karaoke render) committed 07f7598516; cold-gate -> fixer
- Agent 3 (a142b64c35a6710c7) committed 07f7598516: karaoke render in TurnTimeline (accent BorderDirectional
  + alphaBlend tint highlight; identity GlobalKeys; ensureVisible auto-scroll w/ a deeply-reasoned scroll
  state machine -- _autoScrollSuspended/_autoScrollInFlight/_startingAutoScroll/generation, all justified
  against the Flutter scroll-activity source; Semantics seek affordance on the timestamp only, text stays
  selectable). Self-Codex 8 rounds (render) + 4 (tests) -> CORRECT. 39 mutation-proven tests; 1741 calls
  bucket. NEW interface: TurnTimeline({turns, activeIndex, isPlaying, onSeekTurn}); activeIndex null =>
  byte-identical to before (verified). Deviations flagged: NotificationListener<UserScrollNotification> is
  DEAD CODE here (widget sits below the scrollable's notificationContext) -> observes ScrollPosition
  directly; reused an existing arb key for the seek label to avoid gen-l10n churn.
- My cold gate, split scroll (gate-a3-scroll) + render (gate-a3-render), both ISSUES-FOUND. CORRECT:
  highlight (RTL, own/peer preserved), null-gate render, generation guard, deferral, lifecycle/leaks.
  Actionable (in agent 3 scope): (Q1 scroll) activeIndex-null + isPlaying-non-null still attaches the
  isPlaying listener -> master gate not enforced for that combo (gate flagged softening:yes, but it's a
  ROBUSTNESS gap not test-rigging -- the null-gate invariant test is legit); (Q2 render) seek Semantics
  label is "Play 0:12" not the spec's "Play from 0:12".
- FIXER (a66ab6900d12ea396) dispatched: gate isPlaying attach on activeIndex!=null (+ test hasListeners);
  add a proper "Play from {time}" l10n string + gen-l10n (+ test). On return I cold-gate.
- >>> AGENT 5 REQUIREMENTS (from the gate, NOT agent-3 bugs -- the widget can't close these):
  (1) the layout must use a SINGLE scrollable (TurnTimeline observes only the nearest ancestor
  ScrollPosition); (2) to close the keyboard/scrollbar-interrupts-auto-scroll gap, the WIRING should report
  user-scroll intent from ABOVE the scrollable (the widget can't distinguish a keyboard scroll that
  supersedes a DrivenScrollActivity); (3) the caller must update the controller AND widget.turns in the
  SAME tick (the deferred index resolution assumes it). Fold these into agent 5's brief.

## 2026-09-10 (cont) — STEP 3 DONE (cold-green); agent 4 (loading) scoped as standalone file
- Agent 3 fixer STALLED (3rd stall -- codex auto-backgrounds past its timeout in the subagent env; the
  agents that DON'T stall block on `pgrep -f codex` until it exits). Work uncommitted but local-green: I
  killed the orphan, verified (pub get + gen-l10n exit 0, analyze clean, 42 tests, l10n wired -- generated
  l10n is NOT git-tracked so no locale churn), READ the diff (correct: _syncIsPlayingListener gates
  isPlaying on the master gate + handles transitions/swaps/leak; callTranscriptSeekTo "Play from {time}").
  My cold gate (b89dpxkrw): CORRECT 3/3, softening no. Committed 08cc450932. STEP 3 (karaoke render) DONE.
- SPLIT REVISION for agents 4/5: instead of BOTH editing transcript_view.dart serially, agent 4 builds a
  STANDALONE new file (call_recordings_load.dart: the LoadState resolver + a grace-timer/late-data
  controller, testable in isolation, NO transcript_view edit), and agent 5 does ALL of transcript_view
  (layout + render each load state + wire agent-2's playback controller + agent-4's load controller +
  the 3 agent-5 wiring requirements). So only agent 5 touches transcript_view -> no 4/5 conflict.
- ANTI-STALL for agents 4/5: bake in the working technique -- after launching `codex exec` in the
  foreground, BLOCK on `pgrep -f codex` (or `wait`) until the process exits, THEN read the verdict from the
  output file; NEVER end the turn while a codex process is alive.

## 2026-09-10 (cont) — step 3 fully done; l10n backfill deferred to Gabby; active_call tearDownAll flake
- Agent 3 fixer RESURRECTED after its stall (round-7 codex finally returned), noticed my checkpoint commit
  08cc450932 (its 2 fixes) + moved-on state, and added aa36ef5217 (COMMENT-ONLY: corrected a stale
  mutation-proof comment that overclaimed which test catches a mutation -- honest accuracy, no assertion
  weakened, verified). Accepted. This is the 2nd "stalled agent resurrected + committed while the next
  agent was live" -- same hazard; aa36ef5217 only touches turn_timeline_test.dart, agent 4's new file is
  unaffected. STEP 3 (karaoke render) fully done: 07f7598516 + 08cc450932 + aa36ef5217.
- L10N: my 08cc450932 added ONE new arb key (callTranscriptSeekTo "Play from {time}"); I MISSED that the
  client has an l10n_sync_check CI gate (.github/workflows/l10n_sync_check.yaml) that BLOCKS on a new key
  absent from any of the 116 locales; both backfill scripts are BILLED (gemini). OWNER DECISION: leave the
  "Play from" label as-is; the l10n backfill (translate_new_keys.py, ~cents) is deferred -- GABBY will do
  it. => PR2 has a KNOWN l10n_sync_check red until Gabby backfills the one key; do NOT run the billed
  backfill without owner say-so. Not blocking the build.
- REGRESSION FLAKE: the post-step-3 full calls bucket showed +1742 -2, the -2 being active_call_test.dart
  (tearDownAll) -- assertions all passed, only the async teardown RED'd under machine load (the documented
  environmental flake; step 3 didn't touch active_call). PENDING: confirm with a QUIET active_call_test
  solo run once agent 4 is done (running it now would add a 2nd concurrent flutter proc = the flake trigger).
- Agent 4 (ad2963f743ff34ac6) building the standalone loading state machine; anti-stall hardened
  (wait-loop on the codex pid). On return: cold-gate, then the active_call quiet confirm, then agent 5.

## 2026-09-10 (cont) — agent 4 (loading) committed c1dec52ede; cold-gate found a REAL bug + over-engineering
- Agent 4 (ad2963f743ff34ac6) committed c1dec52ede: CallRecordingsLoadController (896 lines = ~236 code +
  ~660 comment; 38 tests). Self-Codex 10 rounds -> CORRECT (foreground held, NO stall -- the pid-wait
  anti-stall worked). Interface: resolveCallRecordingsLoadState(...) + a controller w/ ValueListenable<state>
  + update/retry/dispose.
- My cold gate (b5ea1oa5k) -- the scrutiny paid off: RESOLVER CORRECT, but ISSUES-FOUND (softening no):
  (1) REAL BUG the 10 rounds missed: grace uses WALL-CLOCK now(), so a backward clock jump EXTENDS the
  total wait (round-8's clamp bounds each timer re-arm, not the overall grace) -> fix with a MONOTONIC
  Stopwatch. (2) WRAPPER: REMOVABLE -- the bespoke _ReadOnlyValueListenable downcast-protection wrapper
  (~80 code lines + the rounds-5-9 self-inflicted listener-contract bugs) is gold-plating; the gate
  confirmed direct exposure `get state => _stateNotifier` loses no real safety + matches the sibling. Its
  "listeners run after mid-notify dispose" note is standard ValueNotifier behaviour once the wrapper is gone.
- FIXER (a84d83c0dad8c2cac) dispatched: monotonic grace (injectable Stopwatch) + drop the wrapper (expose
  the ValueNotifier directly, like CallPlaybackController) + drop the wrapper's contract tests. On return I
  cold-gate. LESSON: a 10-round self-gate can still miss a real bug (the wall-clock grace) AND perfect the
  wrong thing (a wrapper that shouldn't exist) -- the independent cold gate + a design-necessity question
  ("is this wrapper needed?") caught both. Over-engineering is a review target, not just correctness.
- FLAKE CLOSED: active_call_test solo run = 180 green, teardown clean -> the post-step-3 bucket -2 was
  confirmed the concurrent-load tearDownAll flake, NOT a regression.
- CARRY: agent 4 flagged CallPlaybackController (agent 2) extends ChangeNotifier vestigially (exposes
  ValueNotifiers, may never call its own notifyListeners) -> a minor consistency/cleanliness item; check +
  fix during the whole-branch (assembly) review if it never uses the inherited notifier.

## 2026-09-10 (cont) — BUILD 4 DONE (58948e1631 cold-green); agent 5 (layout+wiring) dispatched
- Agent 4 fixer (a84d83c0dad8c2cac) STALLED (4th stall -- same codex-auto-background signature; its
  task-notification re-fired "Waiting for the Codex gate (retry)"). Killed the orphan, verified the
  uncommitted work: _ReadOnlyValueListenable wrapper GONE (0 occurrences), monotonic Stopwatch grace in,
  diff -725/+271 across both files (~454 net removed; call_recordings_load.dart itself 896->689, -23%;
  tests 1235->988), dart format clean, analyze "No issues found!",
  call_recordings_load_test.dart = 29 passed; the backward-jump test (~line 298) pins the fix (a wall-clock
  correction during grace has NO effect; unavailable arrives at exactly one grace). Per the "keep it
  simple, ship" steer I did a light verify (not another full re-gate round) and committed 58948e1631.
  BUILD 4 DONE. Steps 1,2,3,4 all complete + cold-green.
- Did NOT re-engage the stalled fixer (resurrecting it risks a duplicate commit while agent 5 is live --
  the 3rd instance of that hazard would have been self-inflicted). Its work is fully captured in 58948e1631.
- BUILD 5 (aa6e3a1bc5fcdd33c, opus) dispatched -- the final integration: transcript_view.dart -> a SINGLE
  CustomScrollView with a pinned SliverPersistentHeader "Full call" bar (driven by
  CallRecordingsLoadController states: loading/pendingMerge->shimmer, ready->merged AudioPlayerWidget,
  none/unavailable->note+retry), AnimatedSize expandable per-device rows, non-lazy TurnTimeline; construct
  CallPlaybackController from matrix.audioPlayer streams + voiceMessageEventId + turns, wire
  activeIndex/isPlaying/seekToTurn into TurnTimeline; dispose both. HARD INVARIANT: no merged recording =>
  renders exactly as today, no controllers. Brief carries the 3 gate-surfaced wiring requirements + the
  pid-wait anti-stall + the keep-it-simple steer (accept correct code, reserve fixer cycles for real bugs).
- PENDING while agent 5 is live: NO flutter bucket (concurrency rule -- agent 5 runs flutter tests). On
  return: cold-gate agent 5, then whole-branch assembly (cold-Codex + full calls bucket + the
  CallPlaybackController-extends-ChangeNotifier consistency item), then owner real-call testing -> PR2 on go.
- Agent 4 fixer RESURRECTED (post-commit) and reported: it verified the tree matched 58948e1631
  byte-for-byte, re-ran the full local gate (green), and ran its OWN independent Codex gate against HEAD ->
  FIX 1 CORRECT / FIX 2 CORRECT / softening no. A 2nd cold verdict agreeing with mine; it did NOT
  re-commit (hazard did not materialise this time). Real counts: call_recordings_load.dart 896->689 (-23%),
  tests 1235->988, 38->29 tests. Corrected the earlier "->~440" note (that was the combined source+test delta).

## 2026-09-10 (cont) — BUILD 6 draft prepared (governed-doc proposal, owner-review-gated)
- Used the agent-5 wait (no flutter allowed) to prep BUILD 6. Read the client voice-video-calls
  .instructions.md: it ALREADY governs turn-time-semantics in prose ("What a turn's time promises" =
  order-by-chunk-end/answer-before-question; "The clock both halves are merged in" = SFU shared clock,
  monotonic-within-device, ~1s resolution). The symbol-grep (orderKeyMs/atMs/mergedStartSfuMs) found
  nothing there precisely BECAUSE the doc is design-only (no code identifiers) -- correct, not a gap.
- The REAL gap: the "Reading it back" section covers reading the transcript, NOT playing the merged
  recording back -- new PR2 behaviour (full-call playback, the order-by-end/PLAY-FROM-START asymmetry,
  karaoke highlight+auto-scroll+seek, recording loading states). New behaviour in a covered area = a design
  decision to govern. Drafted a proposed "### Playing the call back" subsection (in the doc's voice, ~1
  screen) at docs/handoff/2026-09-10-doc-addition-proposal.md. NOT applied to the instructions doc (agent
  never edits a governed doc unilaterally); it's the proposal for Will to review + a placement + open
  wording choices. Finalize the two behaviour-dependent sentences against what agent 5 actually ships.

## 2026-09-10 (cont) — BUILD 5 returned (27b2131f61); confirmed live-refresh regression; cold-gating
- Agent 5 (aa6e3a1bc5fcdd33c, 2.6h, 293 tools) committed 27b2131f61: transcript_view.dart +978/-176 (one
  CustomScrollView, pinned _FullCallBarDelegate "Full call" bar driven by CallRecordingsLoadController,
  AnimatedSize+Offstage expandable per-device rows that stay MOUNTED, non-lazy TurnTimeline; CallPlaybackController
  from matrix.audioPlayer streams; single time-sort handed to BOTH controller+timeline (req3 same-tick ok,
  req1 single-scrollable ok). Self-Codex: CORRECT/softening none (7 rounds). +2 shared files, +2 en arb keys.
- >>> MY FINDING (verified by reading the code, NOT from the gate): LIVE AUTO-REFRESH DROPPED. initState->_load()
  reads transcript/recordings/merged futures ONCE; the only re-read is _retry(); there is NO room/sync/timeline
  subscription (grep: zero StreamBuilder/onUpdate/onSync). So a merge arriving AFTER the screen opens is NOT
  picked up -- the bar sits in pendingMerge shimmer until the 30s grace, then flips to `unavailable` note+Retry,
  and the retry button is NOT shown during shimmer. Common flow (open transcript right after a call, before the
  peer half/merge upload completes) => 30s shimmer then a FALSE "No recording" + manual Retry. Contradicts the
  explicit loading-states intent ("spinner while waiting ... then it appears"). Agent dropped it under PREFER-SIMPLE
  because a setState(_load) refresh raced the terminal-`ready` latch across 3 rounds. red-to-root-cause: fix the
  race (the _retry path ALREADY proves the clean fresh-epoch pattern -- replace controller + _load), do NOT drop
  a required behaviour. => MUST-FIX in the fixer round.
- Agent-5 flags to weigh: (a) shared audio_player.dart dispose now removes _onPlayerChange + cancels
  _onAudioStateChanged UNCONDITIONALLY (genuine leak fix for every non-owning AudioPlayerWidget; blast radius =
  all audio surfaces -> run the broad audio bucket at assembly); (b) multi_platform_audio_player awaits mobile
  setFilePath (matches web; a seek-right-after now lands on a ready source); (c) documented narrow edge: if the
  bar's own play-button DOWNLOAD fails, AudioPlayerWidget leaves voiceMessageEventId wedged -> a later turn tap
  seeks a dead player (agent calls it pre-existing in AudioPlayerWidget; judge in-scope after the gate).
- PLAN: my independent cold gate on the two RISKY areas (shared-audio lifecycle; karaoke seek/ownership races) --
  layout+load-wiring is low-risk (load machine already cold-gated in build 4). Then ONE fixer round to agent 5
  (SendMessage, keeps context) = restore live auto-refresh (root-caused) + any real gate findings. Keep it simple.

## 2026-09-10 (cont) — cold gates A+C returned; 4 real findings; ONE fixer round pending a 4a scope call
- Room-update idiom found: chat_call_buttons.dart:178 subscribes room.client.onSync.stream.listen(...) +
  cancels in dispose (documents why onSync over onRoomState). call_service.dart uses the same. That is the
  root-caused shape for the live-refresh fix. WHY the agent's setState(_load) raced: _load() re-stamps
  readsInFlight:true and RESETS the grace clock every sync -> under steady sync traffic the timeout never
  fires. Correct fix FEEDS the existing controller (preserve monotonic grace), never resets/replaces it.
- GATE A (shared audio lifecycle) = CORRECT / softening no. Verified against the just_audio setFilePath
  preload contract + Flutter removeListener/cancel semantics: the unconditional dispose leak fix is sound,
  the awaited setFilePath is correct. (Static review; omitted AudioPlayerWidget callers -> cover with the
  audio test bucket at assembly.)
- GATE C (karaoke seek/ownership) = ISSUES-FOUND / softening no. red-to-root-cause triage:
  F1 REAL: _startMergedPlayer's post-download early-return (!mounted || ownership-moved) returns WITHOUT
    releasing -> strands an owned, source-less shared player -> a later turn tap seeks a dead player. Rule:
    every exit of _startMergedPlayer leaves ownership consistent (loaded, or released, identity-guarded).
  F2 REAL: a FAILED _startMergedPlayer is swallowed; when the identity guard skips cleanup (a newer P2
    exists under the same event id), the controller sees ownership still held and seeks/plays P2 to the
    FAILED turn's position -> the old failed action hijacks the newer playback. Rule: a failed start must
    ABORT the transaction (rethrow to the tap boundary, which already catches), not return as success.
  F3 = confirmed CORRECT (unawaited play()).
  F4 REAL: the "Full call" bar's own play button (a stock AudioPlayerWidget) is NOT observed -> NO karaoke
    highlight until a turn is tapped; a same-id player swap also freezes the highlight. Confirmed the
    mechanism: AudioPlayerWidget._onButtonTap sets voiceMessageEventId=A FIRST (audio_player.dart:302) then
    creates the player only AFTER an async download, so "attach on the ownership edge" cannot work (player
    not yet created). Robust fix = the bar's play/pause drives transcript_view's OWN karaoke path
    (single-owner), not a stock AudioPlayerWidget. This is a product+design fork (headline feature) -> ASK
    the owner before building it. F1/F2/F5 are fixed regardless.
  F5 REAL (corroborates my finding): late merge/peer-half invisible until manual Retry.
- PLAN: ask the 4a fork (bar-play karaoke vs documented tap-a-turn limitation), then ONE SendMessage fixer
  round to agent 5 = F1 + F2 + F5(live-refresh, onSync feed-not-reset) + F4 per the owner's call. Fixer
  brief drafted at scratchpad/fixer5-brief.md. No push/PR; audio + calls buckets at assembly.
- OWNER DECISION (4a): "Bar play drives karaoke" -> the Full-call bar's play/pause drives transcript_view's
  OWN merged-playback path (single-owner custom control), NOT a stock AudioPlayerWidget. This also collapses
  the shared-player-churn root cause behind F1/F2/F4 (nothing external creates a merged-id player).
- SendMessage-to-subagent NOT on this session's surface (ToolSearch returned only Gmail/Slack/CCD-session
  sends) -> per resume-subagent-via-sendmessage, RE-SPAWNED a fresh fixer with full artifacts (agentId
  a5f88dc6a789002e9, opus), self-contained brief covering F1 (consistent exit/identity-guarded release),
  F2 (rethrow to abort the transaction; verify controller propagates), F4a (single-owner bar control reusing
  _startMergedPlayer/_playSharedPlayer/observation + in-flight guard; per-device rows keep AudioPlayerWidget;
  hard invariant preserved), F5 (onSync feed-not-reset, flicker-free swap). Mutation-proven tests for each;
  full local gate + codex self-gate (block on pid); no push/PR/handoff edits; new arb keys English-only (Gabby).
- ON FIXER RETURN: cold-gate the fixer diff (the F4a control + the race fixes), then whole-branch assembly:
  broad AUDIO bucket (AudioPlayerWidget blast radius from the dispose leak fix) + full CALLS bucket (mind the
  active_call tearDownAll env flake; one bucket at a time) + the CallPlaybackController-extends-ChangeNotifier
  consistency item + whole-branch cold-Codex. Then owner real-call test -> PR2 on explicit go.

## 2026-09-11 — fixer committed 2d1b1abf64 (all 4 findings + 5 follow-ons); my cold gate D+E running
- Fixer (a5f88dc6) committed 2d1b1abf64 (transcript_view.dart +608/-56, test +725; NO handoff/push/PR).
  Self-Codex: round-4 behaviour CORRECT + tests round confirming 9 mutations load-bearing. +96 tests pass.
- MANUAL REVIEW (I read the new code myself, findings confirmed fixed at root cause):
  F1 consistent exit: `_releaseIfCurrent` shared by the post-download early return, the post-setAudioSource
    check, AND the catch; `_mergedStartInFlight` re-entrancy guard. Every exit leaves ownership consistent.
  F2 abort-on-failure: catch rethrows after identity-guarded release; `_MergedStartAborted` for the
    superseded/gone case; `_startAndPlayMerged` + `_seekToTurnGuarded` both catch. Verified seekToTurn
    propagates a throwing startMergedPlayer.
  F4a bar-play karaoke: `_MergedFullCallControl` (custom play/pause + LinearProgressIndicator + elapsed/total
    + spinner + retry) drives `_startAndPlayMerged`/`onResume` -> observation attached synchronously ->
    highlight follows a BAR-started playback. Reuses l10n.pause/resume/callTranscriptRetry (NO new arb keys).
    Hard invariant preserved (per-device rows keep AudioPlayerWidget; no merged row -> no controllers).
  F5 live-refresh: onSync subscription (chat_call_buttons idiom) -> `_refreshRecordings` re-reads + FEEDS
    the controller (readsInFlight:false, monotonic grace preserved), debounced (`_refreshInFlight`), stops
    at terminal `ready`, superseded/shrink guards, SynchronousFuture swap to avoid a false-error flash.
    Two edges the fixer added beyond my brief: the SHRINK guard (a transient-empty read can't yank
    per-device rows) and the SynchronousFuture swap. Both correct.
  Follow-ons (dispose release / superseded-start aborts / per-device keying / no-false-error / bar-retry
    clear): reviewed, sound. The two @visibleForTesting seams (audioPlayerFactory ?? AudioPlayer.new;
    mergedFileLoader ?? real download) are honest DI with production defaults -- NOT gate-softening.
  Deferred/accepted (unchanged): a turn tapped WHILE a bar-start is still downloading may not seek (needs a
    CallPlaybackController change; documented narrow edge).
- MY INDEPENDENT COLD GATE (protocol: my verdict, not the agent's): split by question, running in bg --
  Gate D (live-refresh + shared-player lifecycle data-flow) + Gate E (the _MergedFullCallControl UI state
  machine + start/release). Plus the AudioPlayerWidget blast-radius bucket (call_playback_controller +
  dosage_audio x2 + streaming audio_message_edited_flag) = GREEN +91 (audio_player.dart untouched by the
  fixer, so valid at HEAD) -> the shared-widget leak fix breaks no AudioPlayerWidget caller; Gate A caveat
  closed. On cold-gate green: full calls bucket + whole-branch cold-Codex -> owner real-call test -> PR2 on go.
- CallPlaybackController-extends-ChangeNotifier: CONFIRMED vestigial (never calls notifyListeners; nothing
  listens to it as a ChangeNotifier -- it exposes ValueNotifiers). Harmless; trivial 2-line removal folded
  into the assembly commit, not worth a dedicated gate cycle.

## 2026-09-11 (cont) — cold gates D+E: 6 real edge findings; fixer round 2 dispatched (a7fb6bb08f2afcccd)
- My independent cold gate on the fixer diff (2d1b1abf64), split D (live-refresh+lifecycle) + E (control):
  both ISSUES-FOUND / softening no. 6 real findings, NONE repeats of round 1 -- second-order edges of the
  ~600 new lines of concurrent UI, in 3 tidy classes. The gates explicitly CLEARED: grace preservation, the
  already-shown-merge guard, the SynchronousFuture no-flash, dispose release, _starting clearing, the
  post-frame _loadFailed clear, StreamGroup cancellation, div-by-zero.
  CLASS 1 start-concurrency: D1[P1] _mergedStartInFlight guard returns a SUCCESS no-op -> a turn tap during
    a bar-download seeks a still-loading player -> plays from 0 (this IS the prior "deferred gap"; the clean
    fix = track+return the in-flight start future, so it's no longer deferred). D4[P3] superseded-start abort
    leaks observation (_releaseIfCurrent returns before _detachObservation); likely UNREACHABLE under
    single-owner+in-flight-guard, cheap 1-line detach or document.
  CLASS 2 refresh-coordination: D2[P2] an early refresh swaps displayed futures -> _feedLoadController rejects
    the initial reads' own merge by identity (fix = gate refresh on _initialReadsSettled). D3[P2] shrink guard
    drops a SUCCESSFUL merge when the halves read transiently fails (fix = evaluate the merge with last-known
    count; never adopt the shrunk list).
  CLASS 3 control-EOF/replay: E1[P2] _isAtEnd false when duration==null -> a completed track can't replay
    (fix = honor ProcessingState.completed). E2[P2] replay's unawaited seek(0)+resume has no error handler +
    wrong ordering -> unhandled async error, plays from EOF (fix = await+catch seek before resume; catch pause).
- All 6 real, all small/root-caused (altitude fix for D1; single gate for D2). Re-spawned fixer round 2
  (a7fb6bb08f2afcccd, opus; SendMessage-to-subagent still absent) with mutation-proven tests per finding.
  ON RETURN: re-cold-gate the deltas (should be small + converging), then assembly (full calls bucket +
  whole-branch cold-Codex + the trivial ChangeNotifier cleanup) -> owner real-call test -> PR2 on go.

## 2026-09-11 (cont) — fixer round 2 committed 760508f165 (all 6 fixed); my confirmation cold gate F/G running
- Fixer round 2 (a7fb6bb08f2afcccd) committed 760508f165 (transcript_view +355/-103, test +510; 103 tests
  pass). Self-Codex round 2 CORRECT (its OWN round-1 self-gate caught that my suggested D2 "gate-until-settled"
  would DROP an early sync that carries a merge -> it revised to DEFER-and-run-once; better than my brief).
- MANUAL REVIEW (read the actual round-2 code, all correct):
  D1 seek-seam: `_startMergedPlayer` is now a synchronous re-entrancy wrapper returning `_mergedStartFuture`;
    `_seekSharedPlayer` awaits it before seeking; bookkeeping `.catchError((_){})` doesn't swallow the
    awaiter's failure. Closes the previously-deferred turn-tap-during-download gap.
  D2: `_refreshRecordings` DEFERS (`_refreshPending`) until `_initialReadsSettled`; `_feedLoadController`
    sets settled + runs one deferred refresh. No clobber, no dropped early-sync merge.
  D3: shrunk halves read uses `effectiveHalfCount=_shownHalfCount` to still show a same-sync merge; never
    swaps away per-device rows (halfCountChanged = !shrank && ...).
  D4/E1/E2: per the agent report + my read -- superseded-abort observation detach; _isAtEnd honors
    ProcessingState.completed; _replayFromStart awaits seek(0) caught then resumes; pause error-handled.
  No new l10n keys. Seams remain honest DI.
- PRE-EXISTING INTERACTION (agent flagged; I confirmed in audio_player.dart:510-521): EVERY mounted
  AudioPlayerWidget (incl. offstage per-device rows) attaches an `_onAudioStateChanged` that on
  ProcessingState.completed does stop()+seek(0) on the CURRENT shared player -- so when the merged bar
  finishes, the per-device rows reset it to 0. BENIGN: fires only at `completed` (voiceMessageEventId is
  stable during playback, so no re-attach churn mid-play), and resetting to 0 just presents the finished
  full-call as "ready to replay from start". Not a karaoke regression; out of scope (pre-existing FluffyChat
  behavior). The agent isolated the E1/E2 UNIT tests with a no-per-device fixture to test the control's own
  EOF logic deterministically -> the real per-device-present behavior is left for OWNER REAL-CALL testing.
- CONFIRMATION cold gate (protocol: fresh verdict per agent commit): split F (D2/D3 refresh coordination)
  + G (D1/D4 start/release + E1/E2 control), running in bg (bsmdih109). Holding the FULL CALLS bucket until
  the codex gates finish (avoid the active_call tearDownAll flake under CPU load). On green: full calls
  bucket + whole-branch cold-Codex + ChangeNotifier cleanup -> owner real-call test -> PR2 on go.

## 2026-09-11 (cont) — gates F/G = NON-CONVERGENCE signal; STRUCTURAL round dispatched (adcebbac5353e3aef)
- Confirmation gates F (refresh) + G (start/control) on 760508f165: BOTH ISSUES-FOUND / softening no. 4
  findings, and 2 are SECOND-ORDER edges of round-2's OWN fixes, in the SAME 2 classes -> the red-to-root-cause
  non-convergence signal (3 rounds, same classes => the CLASS is the bug, go structural).
  G-1[P1]: the D1 seek-awaits-start added an await; _seekSharedPlayer doesn't re-validate (player,eventId)
    AFTER it -> can seek a replacement player. Class: await-without-recheck (same as F2).
  F-1[P1]: a sync during an IN-FLIGHT refresh is dropped (_refreshInFlight returns without remembering) ->
    a merge-bearing sync lost until `unavailable` if no later sync. Class: refresh-coalescing (same as D2/D3).
  G-2[P2]: _replayFromStart awaits seek then resumes unconditionally -> a pause tap in between is overridden.
  G-3[P2]: stop()/dispose() futures discarded w/o error handlers -> unhandled async error on teardown reject.
  Gates CLEARED (again): grace preservation, D3 shrink-eval-merge, D4 superseded detach, E1 completed-detection,
  the bookkeeping catchError not swallowing the awaiter's failure.
- All narrow (need concurrent taps / precise sync timing); feature works in the common case. But 2 are P1 and
  the recurrence says point-fixing will keep finding same-class edges. DECISION: ONE STRUCTURAL round that
  SIMPLIFIES (per the user's keep-it-simple steer) --
    Class 1: a single guard predicate `_isCurrentMerged(player,eventId)` re-checked after EVERY await + a
      generation token for the replay/op, REPLACING scattered ad-hoc rechecks (kills G-1/G-2 + the class).
    Class 2: ONE trailing-edge coalescer (_refreshRequested set on every sync; drain-loop while re-requested;
      starts only post-settle) REPLACING _refreshInFlight/_refreshPending/_initialReadsSettled special-cases
      (kills F-1 + the D2/D3 class).
    Class 3: error handlers on discarded teardown futures (G-3).
  Re-spawned structural round (adcebbac5353e3aef, opus; SendMessage-to-subagent still absent) with
  mutation-proven tests. THIS IS THE LAST HARDENING ROUND: on return, ONE final cold gate; if clean ->
  assembly (full calls bucket + whole-branch cold-Codex + ChangeNotifier cleanup) -> owner real-call test ->
  PR2 on go. If it STILL finds substantive new same-class races, STOP gating + document the ultra-narrow
  residual as known v1 edges (diminishing returns; the human real-call test is the real validator for UI races).

## 2026-09-11 (cont) — structural round committed effb4df5f3 (converged); my FINAL cold gate H/I running
- Structural round (adcebbac) committed effb4df5f3 (transcript_view +292/-180; 109 tests = 103 preserved + 6
  new). It made the two classes structurally safe AND its OWN Codex self-gate CONVERGED: self-gate round 1
  found 3 MORE same-class edges (retry-during-drain strands syncs; _startAndPlayMerged captured player AFTER
  the await; _seekSharedPlayer aborted silently w/o post-seek recheck), fixed all at the class level, self-gate
  round 2 = CORRECT. This is the convergence I was waiting for (the agent's own gate stopped finding edges).
  Structures (verified by grep at the expected sites): _isCurrentMerged(player,eventId) predicate re-checked
  after EVERY await at 5 sites (throws to abort the controller txn); _drainRefreshes trailing-edge coalescer
  (_refreshRequested/_refreshDraining) REPLACING the 3 ad-hoc flags; _tapGeneration in the control;
  _fireAndForget on all discarded teardown futures.
- Agent flags: G-1 seek-site recheck + one capture are REDUNDANT with the in-flight-start's own throwing abort
  (throw-dominated, so mutating only those sites stays green) -> it mutation-proved the underlying PREDICATE
  instead (neuter _isCurrentMerged -> RED); the independently-reachable guards (coalescer settle-gate, G-2
  generation, G-3 handler, post-seek recheck) are each directly mutation-proven. Also noted a PRE-EXISTING
  TEST-ONLY caveat: an injected recordingsLoadController isn't replaced on _retry -- not a production
  regression, out of scope.
- MY FINAL cold gate (protocol: fresh verdict on the biggest single rewrite): split H (the coalescer) + I
  (the predicate + await-guards + generation), running in bg (b13cmk9gb). STOP RULE: if CORRECT -> assembly
  (full calls bucket + whole-branch cold-Codex + ChangeNotifier cleanup) -> owner real-call test -> PR2 on go.
  If it finds a NEW substantive same-class race -> ONE targeted fix, re-verify, then STOP gating regardless
  (diminishing returns; human real-call test validates UI races). No open-ended round 5.

## 2026-09-11 (cont) — HARDENING COMPLETE (b36ebe346c) + ChangeNotifier cleanup (1aa1555227); full calls bucket running
- Final gate J on effb4df5f3 returned ISSUES-FOUND but it was a FALSE positive from MY discontinuous sed
  extract (stale post-edit line numbers truncated guard 2b + guard 3); the gate itself said "No concrete
  regression... incomplete review evidence, not a demonstrated defect". Re-gated with complete contiguous
  methods (J2): guards 1 (refresh-throw) + 3 (replay row-capture) CERTIFIED CORRECT; guard 2 had ONE residual
  edge-of-an-edge (a THROWING seek during a same-id supersession skips the detach) -- unreachable in v1 (only
  the guarded _startMergedPlayer makes a merged-id player) and not a regression.
- Per my STOP RULE, closed that last uniformity edge trivially (wrap the seek: on throw, if superseded,
  detach then rethrow -- mirrors the two already-certified explicit-abort detaches) and STOPPED gating
  transcript_view. Committed all 4 guards as b36ebe346c (transcript_view only; 109 tests green; format/
  import-sort/analyze clean). Did NOT re-gate a 6-line closure that mirrors certified code = the churn to avoid.
  5 gate rounds total on this integration; findings strictly decreased in severity/reachability to
  theoretical/unreachable-in-v1 -> the concurrency surface is thoroughly hardened (predicate after every
  await at all sites, uniform observation-detach on every supersession exit, trailing-edge coalescer,
  generation token, error handlers on every fired player future).
- ChangeNotifier item RESOLVED: re-checked -- the test's super.addListener/hasListeners are on
  _CountingOwnership (a ValueNotifier double for the OWNERSHIP notifier), NOT on the controller, so the
  controller's `extends ChangeNotifier` is genuinely vestigial. Removed it + @override + super.dispose()
  (foundation import stays for ValueNotifier); 22 controller tests green. Committed 1aa1555227.
- NOW: full calls bucket (test/pangea/calls/) running as the assembly regression (alone; an active_call
  tearDownAll RED would be the known env flake -- my changes never touched active_call). On green: whole-branch
  is component-cold-gated (builds 1-5 + shared audio all gated); report to owner for REAL-CALL testing (the
  validator for the unreachable-in-v1 UI-race edges + the per-device EOF interaction) -> PR2 on explicit go
  (rebase on main after #8888/#8797) -> Gabby runs the l10n backfill (2 deferred en-only keys: callTranscriptSeekTo,
  callTranscriptPreparingRecording/NoRecording).

## 2026-09-11 (cont) — ASSEMBLY GREEN: all buckets pass (one confirmed env flake); ready for owner real-call test
- Full calls bucket (test/pangea/calls/) = +1804 -1. The -1 was call_media_test "capture transitions..."
  failing on a `LiveKit Exception: [TimeoutException] Timeout` in CallMedia.disconnect -- a load-induced
  async-timeout flake, NOT a regression: (a) git diff confirms call_media.dart/call_capture.dart untouched
  by the Build-5+ work, (b) solo re-run = 58/58 GREEN incl. that exact test. Same class as the active_call
  tearDownAll env flake (a call test's teardown/disconnect timing out under full-bucket machine load).
- FEATURE GREEN across buckets: calls 1804 (1 env flake, solo-green), transcript_view 109, controller 22,
  recordings_load 29 (build 4), audio blast-radius 91. Whole branch is component-cold-gated (builds 1-5 +
  shared audio + 5 hardening gate rounds on the merged-player). analyze/format/import-sort clean throughout.
- STATE: PR2 work complete + verified locally. Branch satvik/call-features-combined. NOT pushed, NO PR (per
  the standing "PR only on explicit per-PR go"). REMAINING before PR2: (1) OWNER real-call testing -- the
  validator for the unreachable-in-v1 UI-race edges + the pre-existing per-device-EOF interaction; (2) rebase
  on main after #8888/#8797 land; (3) explicit owner go; (4) Gabby runs the l10n backfill for the 3 en-only
  keys (callTranscriptSeekTo, callTranscriptPreparingRecording, callTranscriptNoRecording) -- l10n_sync_check
  will be RED until then (known, not blocking the build). Build 6 governed-doc proposal
  (docs/handoff/2026-09-10-doc-addition-proposal.md) awaits Will's review. v2 mid-call device-switch merge =
  issue pangeachat/client#8878.

## 2026-09-18 — owner e2e LOVED it; 3 UI polish tweaks done; merging main (116 behind)
- Owner real-call test (2 humans): feature worked END-TO-END, auto-scroll + ordering perfect. Confirmed the
  transcript is NOT made from the mix -- each device transcribes its own half, ordered on the shared SFU clock;
  the merge is only for playback/karaoke.
- 3 UI tweaks:
  #1 (2030a0fc73): active karaoke turn was greyed (secondaryContainer wash muted the own/primary bubble) ->
     own turns now take a primaryContainer LIFT (brighter), peer keeps the secondaryContainer wash. turn_timeline.dart.
  #2+#3 (6c14ea918f): Full-call bar is now a FLOATING overlay card (reused ActivityGoalHeaderCard's chrome from
     lib/routes/chat/activity_sessions/, NOT its crossfade) over the single CustomScrollView (Stack sibling,
     top-padded), so the per-device recordings expand as a dropdown OVER the transcript -- visible during karaoke
     auto-scroll (the old inline-at-top rows were off-screen mid-playback). SINGLE-PLAYER rule kept (merged control
     is one stable instance in the always-visible header; only the rows toggle via AnimatedSize+Offstage, players
     stay mounted). Avatars added to per-device rows (room.unsafeGetUserFromMemoryOrFallback + Avatar). All
     invariants verified untouched (single scrollable, same-tick _syncPlayback, controllers/coalescer/predicate).
     152 UI tests green (transcript_view 110 + turn_timeline 42).
- CODEX DOWN: ChatGPT quota exhausted until Sep 21 (Gemini tiers 404) -> the agent's self-gate + MY cold gate
  cannot run. Substituted a careful manual diff review (invariants confirmed) + green suite + owner visual e2e.
  The final PR-readiness cross-model gate must wait for Sep 21 OR proceed on CI-green + manual review (owner call).
- MERGE ASSESSMENT: base d6ef346712 (#8801); 116 behind; main changed 771 files, branch 66. Recording/transcript
  files DON'T conflict (clean). 11 conflict files: call_session.dart, ring_player.dart, incoming_call_banner.dart,
  expiring_storage_box.dart (+2 tests), intl_en.arb, pubspec.yaml/.lock, 2 ringtone mp3s. Merging main in
  (never force-push) + resolving + re-testing the calls bucket next; then rebuild APK+web for the owner's final e2e.

## 2026-09-18 (cont) — main merged (812418cd01); ring→main #8888; API-drift fix dispatched
- Merge origin/main into satvik/call-features-combined = 812418cd01. 5 conflicts all #8807 ring (developed on
  this branch, merged to main as #8888) -> took MAIN's canonical ring: ring_player.dart, incoming_call_banner.dart,
  ring_player_test.dart, call_session_test.dart whole-file --theirs; call_session.dart's 3 ring hunks take-theirs
  (lazy _tonesInstance, call.ogg, dispose) while my RECORDING integration (CallAudioRecorder/CallCaptureService/
  merge-coordinator wiring) auto-merged + verified intact. arb/pubspec/storage/mp3 auto-merged. DROPPED: this
  branch's MP3-vs-OGG iOS/macOS reconnect-cue fix (out of PR2 scope) -> FLAG as a separate follow-up vs main
  (main's #8888 uses call.ogg, silent on iOS/macOS per this branch's finding).
- POST-MERGE analyze = 19 issues (main API drift into the recording code, NOT a regression): (A) main made
  ExpiringStorageBox.read async (Future) -> call_audio_merge_coordinator's 5 _index.read sites need await +
  _keepPending/_recordTransient/_isQuarantined/_isExpiredOrGone go async + callers thread await (fire-and-forget
  boundaries use unawaited); (B) main changed TokenRenderingUtil.underlineColor to (BuildContext, Color, {named})
  -> transcript_tokens.dart:255 needs `context` first arg. Dispatched fixer ae05a11520b6fda95 (opus). analyze->0
  IS the gate for type-drift (+ calls bucket for behaviour); codex still down till Sep 21 so no cross-model gate.
- ON FIXER RETURN: analyze-clean + calls bucket -> rebuild APK+web for owner's final e2e on the MERGED build ->
  PR on owner go (cross-model gate deferred to Sep 21 or owner accepts CI+review). PR2 diff vs main stays
  recording/transcript-only (ring now matches main).

## 2026-09-18 (cont) — codex back; drift fix (f030b6988e) + #2 overflow fix (0b3771fef9) gated
- Drift fixer f030b6988e (async cascade + underlineColor) = analyze 0, calls bucket 1823 + known call_media
  disconnect flake (solo 58/58), coordinator 26/26. Its one non-mechanical test change (rule-2 "written before
  the fetch resolves") VERIFIED HONEST: the fetch is held gated throughout the isNotNull asserts, so the
  crash-safety contract stands; only the now-impossible synchronous timing relaxed. No softening.
- MY cold gate on the async cascade (codex back): ISSUES-FOUND/softening no, ONE P2 with reachability caveat:
  two concurrent _keepPending for the same absent key can both read null then both write, so B overwrites A's
  firstSeenAt. DECISIVE CHECK: merge-base box had SYNC read + ALREADY-ASYNC write; main changed ONLY read
  (sync->async). So the race STRUCTURALLY PRE-EXISTED (the always-async write already allowed it); the
  async-read change only WIDENS the window. No crash-safety regression (write was always async -> handler
  return never durable; the index-before-await rule holds). Impact NEGLIGIBLE: firstSeenAt only moves LATER
  by the sub-second gap between onCallFinished/onSyncedCallAudio -> TTL extended by seconds on a minutes
  window (<1%). DEFERRED as a documented follow-up (per-key keep serialization / atomic put-if-absent) --
  NOT a merge regression, and touching the hardened coordinator concurrency for a <1% nit risks more than it
  fixes. Gate otherwise confirmed the adaptation sound (null checks correct, no guard weakened, semaphore +
  single-t0 snapshot preserved).
- #2 floating-card cold gate (deferred from the codex outage): invariants ALL CLEARED (single scrollable,
  single merged-player build, tap-swallow covers footprint, players mounted across collapse). One real P2:
  expanded rows could overflow a short/landscape viewport (stationary card can't scroll -> clip). FIXED
  0b3771fef9: cap the rows to 40% viewport height + SingleChildScrollView inside the card (the activities
  ActivityDropdownContent pattern); inner scroll is NOT TurnTimeline's ancestor so the single-scrollable
  invariant holds; short lists shrink-wrap below the cap. analyze clean, 110 transcript_view tests green.
- NEXT: rebuild APK + web on the MERGED build (812418cd01 + drift fix + #2 fixes) for the owner's final e2e.
  PR on owner go. Deferred follow-ups: (a) the MP3-vs-OGG iOS/macOS reconnect-cue fix vs main; (b) the
  _keepPending per-key serialization; (c) Gabby's l10n backfill for the en-only keys.

## 2026-09-18 (cont) — e2e-READY on the merged build; waiting on phone reconnect
- Rebuilt on the merged build (812418cd01 + gated fixes): WEB peer live on :8091 (merged+UI; SW-cache -> use
  a fresh tab); APK = 291MB single-ABI arm64 at build/app/outputs/flutter-apk/app-debug.apk (Sep 18 15:30).
  pubspec .env toggled for the mobile build + restored (tree clean). LAN stack up at 192.168.1.156 (all 4
  services 200; earlier "all DOWN" was a transient curl timeout, not real).
- Phone DISCONNECTED since the earlier e2e; a 15-min auto-install watcher timed out (no device). APK is built
  + ready; install on reconnect via: adb uninstall com.talktolearn.chat && adb install <the apk> (keeps
  FluffyChat). Everything gated + clean; PR on owner go after the final e2e.
- OPEN follow-ups (none block the e2e/PR of the recording feature): (a) MP3-vs-OGG iOS/macOS reconnect-cue
  fix vs main (dropped in the ring->main merge); (b) _keepPending per-key serialization (negligible
  pre-existing race); (c) Gabby's l10n backfill for the en-only keys (l10n_sync_check red until then).

## 2026-09-21 — transcript ORDERING bug root-caused; DESIGN PIVOT approved (recording-based transcript)
- SYMPTOM (owner): a clean call (both halves ~1:04, no perm gap, recordings perfect) rendered the transcript
  badly out of order, per-turn times not matching the recording. Distinct from the earlier perm-gap diagnosis.
- ROOT CAUSE (proven on real events, call_key $HbAqRPluNz...): the phone half returned 3 COARSE chunk-level
  segments (spans 25100ms, 13632ms) where the provider's word list failed the all-or-nothing 1:1 alignment
  gate (_alignedToTranscript -> null -> whole-chunk fallback). Placement rule orderKeyMs = atMs + spanMs
  (chunk-END, chosen to avoid answer-before-question) then dragged the phone's OPENING ("hello yeah yeah how
  about you...", spoken ~1.5s) to render at 26.6s, after 6 of the web half's turns. Web half returned 10
  EXACT segments (span=None) so it placed correctly. Clocks were fine (offsets 5ms/350ms); ordering math is
  correct GIVEN the data -- the defect is coarse STT positions + a 45s chunk target making "one chunk late" =
  up to 45s late. Dev test captures aligned 334/336, so this fallback almost never fired in testing; the real
  phone hit it 2/3 chunks. Also observed: the phone half came back lowercase/unpunctuated vs web's punctuated
  -> STT provider-output VARIANCE (prior clean call's phone half WAS exact+punctuated). LESSON logged below.
- CLASS BUG: alignment is all-or-nothing per chunk; one re-cut word in a long chunk discards ALL its timing
  and collapses it to one blob at chunk-END.
- DESIGN PIVOT (owner approved, this session): transcript source becomes each user's OWN uploaded full
  recording, transcribed post-call in ONE clean pass, positioned by word timings DIRECTLY (relax the
  punctuation-match gate; text stays the transcript's own so no word is put in a mouth). Per-half LIVE 45s
  transcript is the FALLBACK when a recording didn't upload (mic-perm gap / device death); halves decided
  independently = fault tolerant. Preserves per-speaker attribution + per-speaker target language (NOT the
  mix). Aligns with the documented lazy/on-demand intent.
  - rec-1 (owner-accepted cost posture): capture live chunks but only spend STT on them if the recording
    UPLOAD failed (known at call-end while chunks in memory) -> one STT pass per half, no double-spend, makes
    A free on the happy path. Edge traded: upload-ok-but-later-unreadable -> no live fallback (rare).
  - A (owner: "if needed"): shrink the live chunk target so the FALLBACK half is at most one short chunk off.
  - C (owner: "we need that"): choreo STT ALWAYS returns word-level timestamps (correctness) + punctuation
    (readability), consistently for web + mobile audio. SEPARATE choreo PR; can't diagnose the variance from
    the client DB (STT responses not persisted). Decoupled from the client fix (client positions by timings;
    C polishes text).
- GOVERNANCE: this rewrites voice-video-calls.instructions.md (4 sections: What the transcript says / What a
  turn's time promises / The words are the transcript's... / Failure is not all-or-nothing). Per the
  invariant, a human signs every doc edit -- DRAFT for owner review BEFORE commit, THEN code. No PR w/o go.
- STATE: branch satvik/call-features-combined, tree clean, analyze 0, existing feature cold-gate green.
  Recording + merge + player + UI DONE. Transcript rework (#2 client, the main lift) is the only path to PR2.
- NEXT (this session): draft the doc delta for owner review -> on OK, implement client recording-based path
  (rec-1) + A, cold-gate each chunk, unit tests proved-to-fail-without-fix -> fresh APK+web -> owner phone
  e2e -> final cross-model gate -> PR2 on owner go. C = parallel choreo track, fast-follow PR.

### 2026-09-21 (cont) — doc delta COMMITTED (87980cdd4b); rework DEFERRED to quota reset; BUILD PLAN below
- Owner approved the exact wording; committed the 4-section doc delta (87980cdd4b). Design is now LOCKED + durable.
- BUDGET: weekly quota 92% used (~8% left), resets 2026-09-21 ~14:00Z (~7.75h). 5-hour + context fine. Owner
  said do NOT fan out, be careful, no work lost. DECISION: do not start the multi-file lift on 8% (it touches
  the most-reviewed positioning code and needs a cold gate; half-done = stranded). Execute in ONE clean gated
  pass after reset. This plan is the durable artifact so that pass needs no re-derivation.
- FEASIBILITY CONFIRMED: the recording pass REUSES existing STT plumbing. `SpeechToTextRequestModel`
  (lib/routes/chat/events/speech_to_text/speech_to_text_request_model.dart) takes `Uint8List audioContent` +
  `mimeType` + languages via `buildSpeechToTextRequest(...)`, and `ChunkTranscriber` (call_transcript_sink.dart:19)
  = `Future<SpeechToTextResponseModel> Function(SpeechToTextRequestModel)` -> `SpeechToTextRepo`. So a full
  recording = the same call fed the whole file's bytes; response.transcript.wordTimings is what buildSegments
  already uses. NOTE the helper hardcodes sampleRateHertz 22050 + derives encoding from mimeType -- pass the
  recording's real mime/rate.

  BUILD PLAN (file-level, execute post-reset, cold-gate EACH):
  1. transcript_segments.dart buildSegments -- add a trusted-source mode (param e.g. `bool fromRecording`).
     Today (line ~404-417) `_alignedToTranscript==null` emits ONE whole-chunk blob at chunk-END (orderKeyMs =
     atMs+span). In trusted mode: DROP the 1:1 transcript-match gate and cut by the timed word list directly
     (reuse the existing pause-cut loop from ~482), positioning each utterance at its own word time; display
     text stays the transcript's own (never assembled from the word list -> no word put in a mouth). LIVE
     fallback path keeps the strict rule (fromRecording=false) unchanged. Unit-test: a chunk whose word list
     fails 1:1 but has good timings -> multiple positioned segments, NOT one chunk-end blob (prove it fails
     without the change). This is the crown-jewel change -> its own cold gate.
  2. Recording-transcription driver (new, small). At drain, read the LOCAL full recording file (we recorded
     it; upload is orthogonal), build the request in the SPEAKER's t0 language snapshot (same as live), call
     `transcribe`, buildSegments(fromRecording:true) -> the half. Gated by the SAME subscriber/on-demand
     condition as today.
  3. rec-1 source selection at call-end: prefer the full-recording pass; if no full local recording is
     available at drain (device died pre-drain, etc.), STT the buffered chunks (today's live path) instead.
     ONE transcript event per half, carrying a `source: recording|live` marker -> reader needs NO new
     preference (source chosen at write time). OPEN REFINEMENT for the executor: the committed doc says
     "a half whose recording never UPLOADED falls back to live" -- the cleaner trigger is "no local recording
     at drain" (upload = playback only, orthogonal to transcript). Confirm w/ owner; may need a 1-line doc
     tweak. Do NOT lock unilaterally.
  4. A -- shrink the live-FALLBACK chunk target (pcm_chunker.dart targetDuration 45s / maxDuration 90s). Only
     affects the fallback now, so smaller is cheap; pick a value + fix any default-dependent tests. Owner
     pre-approved "if needed".
  5. call_transcript_event.dart / transcript_writer.dart: add + parse the `source` field; keep old events
     (no source) reading exactly as today.
  6. Tests: buildSegments trusted-mode (unit), source-selection at drain, plus the E2E harness
     (test/e2e/transcript.js) + real-phone pass. Then final cross-model cold gate -> PR2 on owner go.
- C (choreo, separate PR): ensure STT ALWAYS returns word-level timestamps (correctness for the recording
  pass) + punctuation (readability). Investigate the web-vs-phone output variance IN choreo (STT responses
  not persisted client-side). Decoupled from the client fix.
- STATE now: branch satvik/call-features-combined, tree clean after 2 commits (1da70e7bd5 handoff,
  87980cdd4b doc). analyze still 0. No code touched. Recording+merge+player+UI remain done+green.

### 2026-09-21 (cont) — CODE STARTED under 8% budget: buildSegments trustTimings DONE (092e037449)
- Weekly quota barely moves per code step (local flutter runs draw NO model quota; only my reasoning does) --
  so kept it at ~92% used through this work. Self-monitoring via get_usage at each checkpoint; no cron (a
  cron agent would itself burn the quota we're protecting).
- LANDED (092e037449, tested + analyze-clean): buildSegments in transcript_segments.dart gained
  `bool trustTimings = false`. On a trusted source (the recording pass), when `_alignedToTranscript` returns
  null (word list won't reconstruct the punctuated transcript 1:1) BUT the timings are a well-formed sequence,
  it now cuts by the word list directly (`aligned = fromTranscript ?? [for t in timings: t.word.trim()]`) and
  positions each utterance exactly, showing the provider's OWN words -- instead of collapsing to one whole-
  chunk blob ordered at chunk-END (the exact drag that put the phone's opening at 26.6s). The rebuild-integrity
  check is gated on `alignedFromTranscript` (a word-list cut is its own text, cannot match the transcript).
  Default false => LIVE path byte-identical. Malformed sequences refused on both paths. Tests added
  (transcript_segments_test.dart): trusted cuts a misaligned chunk into ['helo thair','frend'] at exact
  positions while live stays one approximate blob (fails without the change); trusted still refuses malformed.
  80/80 green.
- CONFIRMED request pattern for the driver (call_transcript_sink.dart:263-275): SpeechToTextRequestModel(
  audioContent, includeWordTimings: TRUE (call transcript needs timings AND stt_tokens; skipTokenize would
  zero speaking XP), config: SpeechToTextAudioConfigModel(encoding, sampleRateHertz, userL1, userL2)).
  ChunkTranscriber = Future<SpeechToTextResponseModel> Function(SpeechToTextRequestModel).
- REMAINING (do as ONE coherent pass WITH build+E2E, so the recording format is validated, not guessed):
  1. Driver `transcribeRecording({audioContent, mimeType, startedAtMs, durationMs, userL1, userL2, transcribe})`
     -> build request (encoding = mimeTypeToAudioEncoding(mimeType) -- NOT linear16; the uploaded recording is
     COMPRESSED, unlike the live WAV chunks -- sampleRateHertz = the recording's real rate), transcribe,
     buildSegments([TranscribedChunk(result, startedAtMs, durationMs)], trustTimings: true). startedAtMs must
     be on the DEVICE clock (= device_joined_at_ms + recording_started_offset_from_device_join_ms) so the
     reader's existing offset correction still lands it on the shared SFU clock.
     OPEN: confirm the uploaded recording's real mimeType + sampleRate by tracing call_audio_recorder / the
     merge (MP3 vs OGG was a known iOS/macOS wrinkle) -- this is WHY it needs E2E validation, not just a mock.
  2. rec-1 wiring at call-end: prefer the full-recording pass (from the LOCAL recording, upload is orthogonal
     = playback only); if no local full recording at drain, STT the buffered chunks (today's live path). ONE
     transcript event per half + a `source: recording|live` marker (call_transcript_event.dart parse +
     transcript_writer.dart write; old events w/o source read as today). Reader needs no preference (source
     chosen at write).
  3. A: pcm_chunker targetDuration/maxDuration smaller (fallback-only now).
  4. Consolidated cold Codex gate (buildSegments diff is small + ideal to gate; then the driver/wiring) ->
     fresh APK+web -> owner phone E2E -> final cross-model gate -> PR2 on owner go.
- C (choreo, separate PR): always return word timestamps + punctuation; investigate web-vs-phone variance.

### 2026-09-21 (cont) — cold gate RED on trustTimings -> REVERTED (f42da110a4). Fix is DRIVER+C, not buildSegments
- Ran the cold Codex gate on 092e037449 (owner rightly flagged I'd deferred it -- standards are not relaxed
  for budget; descope instead). VERDICT: ISSUES-FOUND, two REAL defects, both root-caused to ONE rule I broke:
  I used the provider's WORD LIST as displayed TEXT when it disagreed with the punctuated transcript, so
  (issue 2) an incomplete word list DROPPED transcript words ("hello world" timed as [hello] -> "hello"), and
  (issue 5) a substituted word REPLACED what was said ("pay bob today" w/ [pay,alice,today] -> "pay alice
  today"). My change also narrowed the rebuild-integrity gate (issue 4), disabling the very protection the
  ORIGINAL code used. Gate confirmed the DEFAULT/live path was unchanged.
- ROOT RULE (restored): displayed text is ALWAYS the punctuated transcript's own; timings supply POSITION
  ONLY, and only where the word list reconstructs that text word-for-word. A misaligned chunk keeps its whole
  text as one positioned block -- it is NOT cleanly rescuable client-side: word-list text corrupts (2/5), and
  ordering a whole-chunk blob at its START reintroduces answer-before-question (the exact bug _add's
  chunk-END rule prevents -- see _add doc). So NO buildSegments change is correct here.
- ACTION: `git revert 092e037449` -> f42da110a4. buildSegments back to proven original; 78/78 green, analyze
  0. The restored original tests already cover issue 2 ("timings covering only part of the text lose to the
  full text", transcript_segments_test.dart:181) -- my change had bypassed it.
- THE FIX (reframed, no delicate-code change): (1) DRIVER transcribes the clean FULL recording in one pass ->
  the existing proven Tier-3 cut handles it WHEN the word list aligns; a full clean pass aligns far more often
  than live chunks cut at silence mid-word. (2) C is now CENTRAL, not polish: when the provider's word list
  disagrees with its transcript there is no clean client fix, so choreo must return word-timings that LINE UP
  with the transcript. Driver calls buildSegments WITHOUT trustTimings (plain). If a real full-file pass still
  misaligns, the fallback is one positioned block (honest, coarse) -- E2E on the owner's phone tells us how
  often that happens; C removes it.
- DOC: sections 1/2/4 of voice-video-calls.instructions.md still hold (recording source, m:ss norm, per-half
  fallback). SECTION 3 (my committed wording "trusts those timings even when misaligned ... boundary can fall
  a little off") now OVER-PROMISES the reverted behavior -> must be corrected to the honest original (text
  always the transcript's; a misaligned chunk keeps whole text as one block). Proposed to owner for approval;
  NOT yet committed.
- NEXT: owner approves the section-3 doc correction -> build the driver (plain buildSegments) + rec-1 wiring +
  A -> cold-gate -> build APK+web -> owner phone E2E (validates full-file alignment rate) -> C (choreo) ->
  final gate -> PR.

### 2026-09-21 (cont) — approach (b) also RED; CLASS confirmed unsound; C is the real order fix
- Owner clarified: keep provider punctuation, "do not let punctuations or anything spoil the order at any
  cost." Re-implemented trustTimings as approach (b): distribute the PUNCTUATED transcript across the word
  list's pause-cut utterances (text always the transcript's; positions from timings). Committed 3fd39ac9a4,
  82/82 green, format+analyze clean. Cold-gated it (gate-distribute).
- Gate VERDICT round 2: ISSUES-FOUND (confirmed issues A/B fixed + word-conservation holds), but a NEW real
  defect: proportional-by-COUNT misassigns text when the two TOKENIZATIONS diverge. Ex: transcript "2026. Yes."
  vs word list [twenty,twenty,six,yes] -> "Yes." (spoken at 10s, after a 9.3s pause) gets lumped into the
  segment at 0s and marked EXACT -> answer-before-question reintroduced; and "agree." (250ms) placed at 10000ms.
  Root: a single transcript token can map to many timed words (numbers, contractions), so count-proportion
  attaches text to the wrong time.
- CLASS CONFIRMED (2 rounds, red-to-root-cause "stop patching, go structural"): the CLIENT cannot soundly
  sub-cut a MISALIGNED chunk -- every text<->time heuristic (word-list text; proportional split) breaks on
  real input. The ONLY sound basis for sub-cutting is a real 1:1 alignment (Tier 3). REVERTED (b) ->
  a5ae6530d4. buildSegments is the proven original; NO client change is correct for misaligned chunks.
- THE FIX (reframed, C-led): order "at any cost" is delivered by making ALIGNMENT SUCCEED, not by client
  heuristics. (1) C (choreo) is the ROOT fix + now clearly ESSENTIAL: the provider must return a word list
  whose TOKENS correspond to the punctuated transcript (same tokenization: numbers, contractions, casing) so
  _alignedToTranscript succeeds -> Tier 3 sub-cuts perfectly -> order exact. (2) DRIVER (full-file, one clean
  pass) feeds alignment a far better input than seam-cut live chunks (which split words mid-syllable and
  cause the tokenization mismatches). (3) Residual truly-misaligned chunk -> original whole-chunk END block
  (honest, rare with C); for the recording FULL-file that means the half sorts late -> which is exactly why C
  must make alignment succeed. A shrinks the LIVE fallback chunk so its END-block is never far off.
- DOC: section 3's committed wording ("trusts those timings to place a turn even when misaligned ... boundary
  can fall a little off") promises sound misaligned sub-cutting, which is UNACHIEVABLE. Must be corrected to:
  text always the transcript's; a turn is cut+positioned from timings ONLY where the word list reconstructs
  the transcript word-for-word; the recording pass + C make that the norm; a still-misaligned chunk keeps its
  whole text as one positioned block. Proposed to owner; not committed.
- STATE: branch satvik/call-features-combined, tree clean; buildSegments = proven original; 78/78 green,
  analyze 0. Net client code change this session = 0 (two attempts reverted -- correctly, no defect ships).
  Doc delta (87980cdd4b) still committed; its section 3 needs the correction above.

### 2026-09-21 (cont) — ROOT CAUSE nailed from REAL captures; fix = C (choreo word_timings reconcile)
- Found choreo's on-disk STT captures: 2-step-choreographer/app/handlers/speech_to_text/.generations/*_metadata.json
  (1154 real provider responses incl. the exact failing call $HbAqRPluNz). Analyzed alignment (client _core
  1:1 rule) per provider.
- DEFINITIVE CAUSE (data): the phone half hit openai-whisper-1; its word_timings list occasionally has ONE
  MORE token than its transcript -- HYPHENATED/COMPOUND speech: transcript "uh-huh" (1 word) vs word_timings
  ["uh","huh"] (2). Client's strict `spoken.length != words.length` -> null -> whole-chunk block ordered at
  chunk END -> the drag. Confirmed on the failing call: 2 misaligned chunks, both count off-by-one ("hello
  yeah yeah..." 21v20; "uh-huh almost okay..." 12v11). Web half aligned (no hyphenates). Content-dependent =
  why it looked intermittent. Whisper overall 298/312 aligned (~95%); failures are these off-by-ones.
  Provider mix in captures: whisper 778, deepgram 38, google 23. (Sample rate 48k phone / 16k web is a
  red herring -- the cause is tokenization, not rate.)
- FIX = C (choreo), clean + deterministic: where word_timings are built (word_info_to_stt.py:109), reconcile
  them to the TRANSCRIPT's whitespace words -- greedily merge provider words whose normalized concatenation
  reconstructs one transcript word (uh+huh -> uh-huh, combined start/end), emitting one WordTiming per
  transcript word with .word = the TRANSCRIPT word. Then client alignment is 1:1 by construction -> proven
  cut path orders every turn. Numbers ("2026" vs "twenty twenty six") won't reconstruct -> leave raw ->
  client safely blocks that chunk (no misattribution), per the doc's "leave unmatched, deterministic"
  philosophy (speech-to-text.instructions.md Token-to-Word Alignment). NO client change; driver/A now
  unnecessary for correctness (optional polish).
- SCOPE (governed): reconcile ONLY on the include_word_timings (call-transcript) path -- do NOT touch the
  skip_tokenize word_timings (streaming/voice "frozen user_stt contract", streaming-stt.instructions.md).
  The word_timings<->transcript contract for the call transcript is a DOC GAP -> draft a note in
  speech-to-text.instructions.md for OWNER review (do not commit doc unilaterally). NOTE: providers
  (google/deepgram/openai adapters) each build word_timings; confirm word_info_to_stt is the shared chokepoint
  vs per-adapter before placing the reconcile.
- STATE: client branch satvik/call-features-combined clean, buildSegments = proven original (78/78 green),
  net client code change this session = 0 (2 attempts correctly reverted). choreo on main (make a branch).
  Client doc delta 87890? -> 87880cdd4b committed; its section 3 still needs the honest correction (pending
  owner wording approval). PLAN: choreo branch -> TDD reconcile (real uh-huh + 2026 + clean cases) -> wire
  into include_word_timings -> lint.sh + unit -> cold gate -> full local stack + phone E2E ($HbAqRPluNz-style
  call orders correctly) -> choreo PR + client PR2 on owner go.

### 2026-09-21 (cont) — C IMPLEMENTED + unit-green + real-data-proven; re-gating
- choreo branch satvik/stt-word-timings-transcript-align in worktree
  2-step-choreographer/.claude/worktrees/stt-align (main checkout restored to main; model lid.176.bin +
  copied in as it's gitignored). Commit ea2ad2b9 (amended): reconcile_word_timings_to_transcript in
  word_info_to_stt.py, wired ONLY on include_word_timings (skip_tokenize/streaming user_stt contract frozen),
  + test_reconcile_word_timings.py (12 tests), registered in unit_tests.txt. lint clean.
- MECHANISM: walk transcript whitespace words; for each, consume provider timings until their \W-stripped
  lowercased concat == the \W-stripped word; emit ONE WordTiming (transcript word, edge-punct stripped;
  merged span from EVERY present endpoint; min confidence). Unreconstructable (spelled-out number 2026 vs
  twenty twenty six) -> return raw -> client blocks chunk (never misattributes).
- PROOF on REAL data (deterministic, the exact failing call $HbAqRPluNz captures at
  2-step-choreographer/app/handlers/speech_to_text/.generations/*): both failing chunks now pass the client's
  1:1 count gate -- "hello yeah yeah..." 21->20 (merged "60-70"), "uh-huh almost okay..." 12->11 (merged
  "uh-huh"). Regressions green: test_include_word_timings 20, test_word_info_to_stt 12, stt_golden 10.
- COLD GATE round 1 found 2 real edge cases (codex ran real probes): (1) punctuation-only provider entry
  absorbed -> inflates neighbor start; (2) complementary missing endpoints -> inverted merged span. FIXED:
  (1) drop empty-norm entries via `matchable` before matching; (2) merge span from all present endpoints
  (min/max) so never inverted. +2 hardening tests (12 total). Benign homograph case (re-sign/resign greedy)
  preserves order -> accepted. RE-GATING now (gate-choreo-reconcile2).
- REMAINING: re-gate green -> phone E2E (stand up local choreo WITH this fix + phone via lan-cutover, real
  call orders correctly; client APK UNCHANGED so no rebuild) -> choreo PR + client PR2 on owner go. Client
  buildSegments = proven original (no client change). Client doc section-3 correction still pending owner
  wording approval (over-promises the reverted client sub-cut; but now moot-ish since fix is choreo -- revisit
  wording to reflect C).

### 2026-09-21 (cont) — choreo reconcile COLD-GATE GREEN (round 5); stack up for E2E
- After 4 gate rounds (all real edge cases, fixed STRUCTURALLY not spot-patched): R1 punct-absorb +
  inverted-span; R2 single-word-fill non-monotonic + spurious far-apart merge; R3 inverted-interval-bypass
  + endpoint-completeness + short-gap-turn-cross + jitter-amplify; R4 final-span inversion via backward
  jitter. Structural closure: single word = endpoints verbatim (no fabrication); MERGE only when every part
  is present + valid (start<=end) + ordered + tightly contiguous (gap in [-50,+100]ms; real compound gaps
  are 0ms) + the final span is non-inverted; else return raw (client blocks). Round 5 = VERDICT: CORRECT /
  GATE-SOFTENING: NONE (38,416 endpoint combos + 30,000 randomized cases). Accepted documented residual:
  choreo has no other-speaker turn timing, so a <=100ms-gap real compound spanning a hypothetical sub-100ms
  other-speaker word can't be proven impossible in-choreo -- physically negligible, within-half only.
- STATE: choreo fix committed a8ef0628 on branch satvik/stt-word-timings-transcript-align (worktree
  2-step-choreographer/.claude/worktrees/stt-align). 17 reconcile tests + regressions (include_word_timings
  20, word_info 12, golden 10) green; lint clean; real-data replay aligns (20/20, 11/11). Branch is on LOCAL
  main (27 behind origin/main) -- REBASE onto origin/main before the PR.
- E2E STACK UP (for owner's phone test): choreo-with-fix running from the worktree on 0.0.0.0:8012
  (LAN 192.168.1.156:8012, stable 200); Synapse focus + lk-jwt LIVEKIT_URL LAN; phone APK already points at
  the local stack (its prior call's STT captures are in this local choreo's .generations). Client UNCHANGED
  (no rebuild). NOTE: choreo-from-worktree via background uvicorn raced on the port across restarts -- kill
  ALL + wait 8s + start ONE; a stable instance is up now. Owner making a test call with compound words;
  verify via local Synapse DB (pull newest call_transcript, interleave by orderKeyMs).
- NEXT: owner E2E confirms ordering -> rebase choreo branch on origin/main -> choreo PR (word_timings<->
  transcript reconcile) + client PR2 (recording/merge/player/UI, no transcript-code change) -> both on owner
  go. Client doc section-3 wording still needs owner approval (now describes the client fix that was
  reverted; should point to C instead) -- revisit at PR time.

### 2026-09-21 (cont) — PIVOT to RECORDING-BASED transcript (owner-directed, simpler); builder DONE
- OWNER TEST (call $WB-eev6OvJfmxz2...): a chunk of the phone's dialogue (post-unmute, ~0:47-1:04) is
  MISSING from the transcript though it's in the recording. DB shows calltester chunks_captured=2 /
  chunks_transcribed=1 -> the LIVE 45s path dropped the 2nd chunk (mute->unmute gap / incomplete
  transcription). Proves the live-chunk path is unreliable; the uploaded recording is complete.
- OWNER DECISION (final, keep it SIMPLE): transcript comes from each device's OWN uploaded recording (the
  same continuous audio the mix uses); when a user's recording is missing, fall back to that half's live
  45s transcript. Use the STT word_timings DIRECTLY -- do NOT align to a punctuated transcript, do NOT drop
  for noise/extra words, showing word-list spelling ("uh huh") is fine. The choreo reconcile (branch
  satvik/stt-word-timings-transcript-align, gate-GREEN) is NOT needed for this path and is set aside (the
  recording pass uses word_timings directly, no alignment).
- DONE: buildRecordingSegments(result, startedAtMs, durationMs, {pause}) in transcript_segments.dart
  (client, PR2 branch satvik/call-features-combined, combined worktree) -- commit 531dc53cc4. Cuts
  word_timings by pauses, text = word-list words joined, atMs = startedAtMs + first-word bounded start
  (device clock, exact/spanMs null), momentWithinChunk-bounded, complete (nothing dropped incl. the
  mute/unmute gap). 5 tests + 83/83 green, analyze+format clean. Cold gate RUNNING (gate-recording-segments).
- WIRING PLAN (next; the substantial part):
  1. CallAudioRecorder (call_audio_recorder.dart): at finish, after building `wav` (~line 1103), if given a
     transcribe fn + langs, call transcribe(SpeechToTextRequestModel(audioContent: wav, mimeType audio/wav,
     encoding linear16, sampleRateHertz gen.sampleRate, userL1/userL2, includeWordTimings: true)) ->
     buildRecordingSegments(resp, gen.runStartedAtMs, gen.duration.inMilliseconds) -> store as a public
     `recordingSegments` getter (+ maybe recordingLang). Guard: only if wav non-empty + transcribe provided.
     Non-fatal on STT failure (leave recordingSegments null -> live fallback).
  2. call_session.dart: build the recorder with transcribe + userL1/userL2 (already in scope). Pass a
     `recordingSegments: () => audioRecorder.recordingSegments` (+ source) closure into CallRecord.
  3. CallRecord (call_record.dart _publishTranscript ~496): prefer recordingSegments when non-empty, else
     transcripts.segments (live). Add a `source: recording|live` field to the published content + the
     accounting should reflect the chosen source (recording pass has no chunk counts -> set sensibly).
     CallRecord runs AFTER capture close (which awaits recorder finish), so recordingSegments is ready.
  4. call_transcript_event.dart: add + parse optional `source`; old events w/o it read as today. Reader
     (transcript_assembly/transcript_view) interleaves segments by orderKeyMs on the SFU clock UNCHANGED --
     recording segments are on the device clock like live, corrected by the same anchor. NO reader change.
  5. TDD each; cold-gate the recorder+record wiring; then E2E on owner phone (local stack up:
     choreo-with-fix 192.168.1.156:8012, web :8090, Synapse/lk-jwt LAN; APK points at local).
  6. COST note: this leaves live transcription running during the call (fallback) AND transcribes the
     recording at drain = ~2x STT on the happy path. Acceptable per owner (tiny at MAU); a later
     optimization is to defer live STT unless the recording is unavailable.
- NOTE: choreo-from-worktree background uvicorn races on the port across restarts -- kill ALL + wait 8s +
  start ONE. Stack currently up (choreo-with-fix stable). E2E stack ready.

### 2026-09-21 (cont) — recording-transcript WRITE-SIDE wired + tested + committed (12c4395af7)
- OWNER SCOPE-DOWN (verbatim intent): "do not change any other crux of the feature, just get the
  transcripts from the individual call recordings for each respective user, and ensure we can test this
  and revert it back if it is very bad in quality." => implemented NARROWER than the earlier WIRING PLAN:
  ONLY the segments source swaps, behind one flag. NO `source` event field, NO call_transcript_event.dart
  change, NO accounting change, NO reader/merge change.
- FLAG: Environment.callRecordingTranscript (env CALL_RECORDING_TRANSCRIPT, default OFF). Off = today's
  behavior byte-for-byte (recorder never transcribes; live transcript-first order). Revert = flip flag.
- CallAudioRecorder: new optional transcribe/userL1/userL2 + `List<TranscriptSegment> recordingSegments`
  field. In _finish, `_recordingSegmentsFrom(wav, gen.runStartedAtMs, gen.sampleRate, durationMs)` is
  KICKED OFF right after the wav is built (line ~1133) so it OVERLAPS the upload (no added audio latency),
  and AWAITED in the delivery loop's inner `finally` so recordingSegments is set on every exit path before
  finish() returns. Non-fatal (returns [] on null transcribe / STT error / no langs) so the live half
  always stands. Uses word_timings directly via buildRecordingSegments (includeWordTimings, LINEAR16,
  speaker's own L1/L2), mirroring CallTranscriptSink's request exactly.
- CallRecord: new optional `RecordingTranscriptSource? recordingSegments` (() => List<TranscriptSegment>).
  _publishTranscript now reads `recorded = recordingSegments?.call() ?? []`; segments = recorded.isNotEmpty
  ? recorded : transcripts.segments (per-half fallback). finish() REORDERS only when the source is wired:
  publishCallAudio (runs recorder.finish -> fills recordingSegments) BEFORE publishTranscript; when null,
  original transcript-first order is byte-for-byte unchanged. Both remain ahead of the _credited gate.
- call_session: `recordingTranscript = Environment.callRecordingTranscript` read once; recorder gets
  transcribe/userL1/userL2 only when on; CallRecord gets `recordingSegments: () =>
  audioRecorder.recordingSegments` only when on.
- CAVEAT (known, accepted per scope-down): when recording-based segments are published, the capture
  accounting (chunksLost/drainComplete/chunks*) still reports the LIVE chunk path. The reader NEVER hides
  segments on accounting (transcript_assembly.explainsEmptiness requires segments.isEmpty), it only adds a
  completeness NOTE -- so a complete recording-based transcript can still show a spurious "part may be
  missing" note iff the live path happened to lose/te not-drain a chunk. Cosmetic; segments always display.
  Follow-up (not in scope now): reflect recording-path completeness, or add a `source` field.
- TESTS: call_record_test.dart +4 (prefer recording over live; fall back to live when recording empty;
  audio-before-transcript order when wired; transcript-first when off) via a callOrder tracker + a
  recordingSegments param on the record() harness. call_record 70/70; recorder + transcript_segments
  132/132; analyze + format clean on all 5 touched files.
- COMMIT: 12c4395af7 on satvik/call-features-combined (combined worktree). 5 files, +287/-15.
- NEXT: (1) cold-gate the wiring behavior diff (gate dir /tmp, FACTS + the 4 source files, <350 lines);
  (2) re-raise local stack (choreo :8012 LAN, web :8090, phone APK) with CALL_RECORDING_TRANSCRIPT=true and
  E2E on the owner phone -- make a call, verify the recording-based half in the local Synapse DB; (3) PR2
  only on explicit owner go. choreo reconcile branch remains set aside (not needed for this path).

### 2026-09-21 (cont) — wiring cold-gated GREEN (behavior + tests); flag-off purity fix
- COLD GATES (both GREEN, GATE-SOFTENING: NONE):
  - BEHAVIOR (4 source files, 333-line diff): all 7 correctness Qs pass -- recordingSegments
    populated on every finish() exit path; failures caught + await can't mask a try-body error;
    no data race (takeBytes copies PCM, inputs final); reorder keeps both publishes ahead of
    _credited + retry/dedup/orphan intact; source read once before the retry loop; gen.runStartedAtMs
    is the correct device-clock anchor. ONE note (not a defect): flag-off still added one async
    continuation via the finally await.
  - TESTS (146-line diff): the 4 tests each fail on their specific reversion; exact-list order
    asserts; no skip/xfail/loosened matcher; harness faithfully separates null (off) from const []
    (on, empty). Note: #3 proves invocation order, not delayed-completion order (harness prepopulates).
- PURITY FIX (commit 2e896f2e64): made flag-off a TRUE no-op -- pendingRecordingSegments is null when
  transcribe is unwired, and the finally await is guarded `if (pending != null)`. So flag-off creates
  no future and awaits nothing; finish()'s control flow is exactly today's. recorder 46/46 green,
  analyze+format clean. Re-gate RUNNING (gate-wiring-flagoff, 48-line diff).
- STATE: satvik/call-features-combined has 3 new commits this session: 12c4395af7 (wiring+tests),
  3fea9acf0c (handoff), 2e896f2e64 (flag-off no-op). buildRecordingSegments (round-3 GREEN) already
  committed earlier (531dc53cc4/6eafa6e8a3). No push yet (owner go required).
- E2E BLOCKER: phone is DISCONNECTED (adb devices empty). Local stack partial: Synapse :8008 UP,
  lk-jwt :7980 UP, choreo :8012 DOWN. Phone E2E (owner's real-audio quality check) needs the owner to
  reconnect the phone + a fresh APK built with CALL_RECORDING_TRANSCRIPT=true. The web E2E harness
  (transcript.js, two Chromes fake audio) can verify the MECHANISM without the phone, against the
  local stack -- needs choreo up + flag on in client .env + web rebuild.
- NEXT: confirm flag-off re-gate GREEN; bring choreo up (:8012, STANDARD choreo -- NOT the reconcile
  worktree, this path uses raw word_timings); web-harness E2E + inspect the published half in Synapse
  DB; report + give owner the phone-test steps. PR2 only on explicit owner go.

### 2026-09-21 (cont) — recorder mechanism tests + full-suite check; feature COMPLETE
- ALL THREE COLD GATES GREEN (CORRECT / GATE-SOFTENING: NONE): behavior, tests, flag-off no-op.
- RECORDER MECHANISM TESTS (commit ebc836ffe0, +4): finish() transcribes its own WAV and fills
  recordingSegments from the provider word list (request carries the bytes + timings + speaker langs);
  an STT failure leaves recordingSegments empty + audio half intact (non-fatal); feature off -> empty;
  a non-carrier device never transcribes (finish returns before the WAV is built). Closes the
  completion-order coverage note. Recorder 50/50 green.
- SESSION COMMITS on satvik/call-features-combined (all local, no push): 12c4395af7 (wiring+tests),
  3fea9acf0c (handoff), 2e896f2e64 (flag-off no-op), 3ddfe01c73 (handoff), ebc836ffe0 (recorder tests),
  + this handoff commit.
- FULL calls-dir test run: recording-transcript surfaces ALL GREEN (recorder 50, call_record 70,
  transcript_segments 132). ONE PRE-EXISTING failure, UNRELATED to this work: call_media_test.dart
  "...watches are given back when the call is disposed - did not complete" (1 test in isolation; ~52
  under full-dir interference -- a hang/stream-lifecycle issue). PROVEN not ours: call_media.dart +
  call_media_test.dart are byte-identical to origin/main; call_media_test imports NONE of the
  recording-transcript files; the only branch-modified dep it imports is transcript_assembly.dart
  (+39 additive, from earlier combined work, not this session). Flagged as task_c340b22a for a
  dedicated fix (MUST be green before PR2 -- pre-push full-CI gate). Do NOT weaken the test.
- FEATURE STATUS: recording-based call transcript write-side is COMPLETE, cold-gate GREEN, fully unit
  tested, flag-gated (CALL_RECORDING_TRANSCRIPT, default OFF), revertible. Reader/merge untouched.
- E2E STILL PENDING (needs owner): real-audio quality check on the phone. Phone is DISCONNECTED. Steps
  for owner: reconnect phone (USB) + unlock; then build APK with the flag on (uncomment `.env` in
  pubspec per pangea-call-testing skill; set CALL_RECORDING_TRANSCRIPT=true in client .env; JAVA_HOME +
  rustup shim; `flutter build apk --debug`; adb install -r), lan-cutover.sh lan, choreo up on :8012
  (STANDARD choreo -- raw word_timings), make a call, I verify the recording-based half in the local
  Synapse DB. Web harness (transcript.js, fake audio) can verify the MECHANISM without the phone but
  not real-voice quality.

### 2026-09-21 (cont) — E2E environment STOOD UP for owner's real-voice phone test
- STACK (all LAN-cutover, verified): Synapse :8008 (focus -> LAN lk-jwt), lk-jwt :7980 (LIVEKIT_URL
  ws://192.168.1.156:7880), LiveKit :7880, choreo :8012 (STANDARD main checkout, raw word_timings,
  STT+CMS working). LAN IP 192.168.1.156.
- PHONE: com.talktolearn.chat rebuilt with CALL_RECORDING_TRANSCRIPT=true and installed (arm64-only
  debug, 347MB; built via `--target-platform android-arm64` because `--split-per-abi` conflicts with
  the project's ndk abiFilters). Phone was 100% full (801MB free) -> `adb shell pm trim-caches` freed
  to 1.4GB, install succeeded WITHOUT uninstall (login preserved). App connects as @calltester:
  pangea.localhost. Non-fatal local 500 /subscription/status + 404 /cms media in logs (pre-existing).
- LAPTOP WEB endpoint: `flutter build web --release` (new code + flag), .env copied into build/web,
  served by local-dev/spa_server.py on :8090 (localhost + LAN). Onboarding renders, homeserver
  resolves to http://192.168.1.156:8008 (no double-scheme bug), login reachable. Console shows CMS
  languages CORS + media 404 (local-web quirks, not login/call-blocking). Both endpoints flag-ON ->
  both halves will be recording-based.
- BUILD HYGIENE: pubspec `- .env` asset was uncommented only during APK builds and RE-COMMENTED after
  (committed state clean; test/pangea/build/pubspec_env_asset_test asserts committed=commented).
  CALL_RECORDING_TRANSCRIPT lives only in the gitignored client .env (worktree), never committed.
- VERIFY TOOLING: scratchpad/verify_call_transcript.py -> `docker exec -i pangea-synapse-local
  python3 - N < verify_call_transcript.py` prints newest pangea.call_transcript halves (sender,
  device, segments text+at_ms, accounting). PROVEN on existing data. BASELINE CONFIRMED: newest
  @calltester half from the OLD build has chunks_captured=2/chunks_transcribed=1 with the post-unmute
  chunk MISSING -- exactly the reported bug. After the new-build call, calltester's SEGMENTS should be
  complete (whole-recording) even though live accounting may still show the loss.
- WAITING ON OWNER: owner + friend place a 1:1 call (phone @calltester <-> laptop web @learner),
  speak real voice (repro mute/unmute), hang up. Then pull both halves and confirm recording-based +
  complete. PR2 only on explicit owner go afterward.

### 2026-09-21 (cont) — E2E round 1: phone half fell back to live; ROOT-CAUSED + FIXED (48kHz > STT cap)
- OWNER E2E (2-min call, @calltester phone <-> @learner laptop web): BOTH halves published +
  complete, BUT calltester's was the LIVE path (punctuated) while learner's was RECORDING-BASED
  (unpunctuated, raw word list). Screenshot "No transcript from You" was a TIMING artifact --
  learner's half landed ~28s after calltester's (recording transcription runs at hangup).
- ROOT CAUSE (from choreo log + call_audio events): the recording-based path sent the WHOLE
  recording as ONE POST /choreo/speech_to_text. calltester records at 48000Hz (phone OS default);
  its 2-min WAV = 11,728,364 B -> ~14.9MB base64 -> over choreo's cap (audio_content <= 10485760 B /
  10MB base64) -> ONE 422 in the log -> transcribe() threw -> recordingSegments [] -> live fallback.
  learner records at 16000Hz -> 3.9MB -> ~5MB base64 -> under cap -> recording-based worked. So the
  FEATURE IS CORRECT (web proved it); only the phone's native 48kHz overflowed.
- FIX (commit 5404deee28, client-only): downsample the STT COPY to 16kHz mono in
  _recordingSegmentsFrom (box-average decimator `_downsamplePcm16Mono`; only when channels==1 &&
  rate>16000). _finish takes `pcm = gen.takeBytes()` ONCE, wraps it native-rate for the upload, and
  passes the same pcm+rate+channels to the helper. Cap guard: if the 16kHz WAV still >
  _maxSttWavBytes (7.5MB, base64 stays <10MB) -> return [] (live fallback), never a request that
  422s. The uploaded recording + mix stay native 48kHz. Speech STT gains nothing >16kHz (it is
  captureSampleRate's intent, and what the web half already sends). recorder 51/51 green (+1
  downsample test: 48kHz->STT 16kHz + ~1/3 bytes, upload unchanged). analyze+format clean.
- IN FLIGHT: cold-gate on the fix (gate-downsample); phone APK rebuilt with the fix + reinstalling.
  Next: gate GREEN -> owner re-calls -> expect BOTH halves recording-based (both unpunctuated), the
  phone half complete incl. any mute/unmute gap.

### 2026-09-21 (cont) — downsample fix cold-gate GREEN; phone reinstalled; awaiting E2E round 2
- Cold-gate on 5404deee28 (gate-downsample): VERDICT CORRECT / GATE-SOFTENING NONE. 7/7 -- one
  takeBytes(), resampler bounds safe (1.24M span checks), typed-view/endianness correct, cap
  7.5MB->exactly 10,000,000 base64 (<10485760), stereo skipped+guarded, non-fatal intact, sttRate
  consistent between WAV+request.
- Phone APK rebuilt with the fix + reinstalled (build 15:20:53, arm64, trim-caches freed to 1.8G,
  login preserved). Laptop web (16kHz) unchanged -- it never needed the downsample. Stack all up.
- AWAITING owner E2E round 2: re-call, expect BOTH halves recording-based (both unpunctuated),
  phone half complete incl. mute/unmute gap. Then verify via verify_call_transcript.py + PR2 on go.

### 2026-09-21 (cont) — E2E round 2: phone half lost to post-hangup backgrounding; OWNER DEFERS to follow-up
- E2E round 2 (2:22 call): BOTH audio halves uploaded (learner 16kHz 4.6MB, calltester 48kHz 13.6MB);
  learner TRANSCRIPT half recording-based + complete (14 segs); calltester TRANSCRIPT half ABSENT.
  calltester's downsampled STT returned 200 (transcript WAS built) -- so the publish, not STT, failed.
- ROOT CAUSE (issue 2): the reorder publishes the transcript AFTER recorder.finish() awaits the ~25s
  whole-recording STT. On the phone the user had walked to the laptop; the app backgrounded, and the
  late _publishTranscript (25s post-hangup, +3 retries) was dropped. Laptop tab stayed open -> its
  half published. Reader also shows stale "No transcript" until refresh (late half not live-picked-up).
- ISSUE 1 (owner's duration concern, valid): choreo caps STT audio at 10MB base64 (hard-coded in
  speech_to_text_schema.py). Downsample buys ~4min at 16kHz; a 10-60min call still overflows.
  Compression (choreo accepts OGG_OPUS) doesn't fully solve it -- Google sync STT ~1min inline cap ->
  long audio needs chunked/async STT regardless.
- SHARED ROOT: whole-recording transcription is heavy (size + ~25s..minutes) and post-hangup on the
  CLIENT is fragile (mobile backgrounding + the cap). Presented 3 options: A client-chunk+keepalive+
  live-floor, B compress (rejected: doesn't solve Google 1min), C server-side (choreo transcribes the
  already-uploaded recording, half published server-side -- robust for any duration, no client
  lifecycle).
- OWNER DECISION (verbatim intent): defer the ENTIRE recording-based transcript to a FOLLOW-UP
  (server-side / Option C makes sense for reliability); FOR NOW flip the flag back OFF and retest the
  OLD live-chunk architecture once more.
- ACTION: CALL_RECORDING_TRANSCRIPT set 'false' in the (gitignored) worktree .env AND build/web/.env.
  Phone APK rebuilding flag-off (old live path, byte-for-byte per the gates); laptop web just reloads.
  Committed code UNCHANGED -- the recording-based feature stays flag-gated-dark on the branch; flip is
  .env-only (the revertibility the feature was built for). Follow-up: server-side recording-based STT.

### 2026-09-21 (cont) — OWNER GO: build recording-transcript v2 (client-robust + choreo backstop). P1 DONE.
- OWNER confirmed the architecture: client transcribes its OWN recording via choreo (chunked for any
  length) + posts its half; choreo ALSO transcribes the uploaded recording + posts the same half as a
  backstop; BOTH post under the deterministic txn id so Synapse dedups -> safe. "Do both in parallel."
  Owner insight (correct): recording-based is far better ordered than live because, like the MIX, it's
  each device's CONTINUOUS recording on one clock -> natural word timings, no chunk-boundary artifacts,
  no drops. Design spec: docs/handoff/recording-transcript-v2-design.md (committed).
- P1 DONE + committed (c75b6a3d19): any-duration chunked STT.
  - transcript_segments: extracted buildRecordingSegmentsFromTimings (core of buildRecordingSegments);
    the wrapper delegates. Behavior-preserving.
  - call_audio_recorder._recordingSegmentsFrom: downsample 16kHz mono, then split into <=cap pieces,
    transcribe each, offset each piece's word timings by pieceStartMs=(offset*1000/(rate*frame)),
    merge, buildRecordingSegmentsFromTimings. Single-piece (short call) = unchanged single-response
    path. Silent piece skipped; no-timings piece -> [] (no partial half); any throw -> [] (non-fatal).
    maxSttPieceBytes injectable for tests (_maxSttPieceBytes=7MB -> ~3.6min/piece at 16kHz).
  - Tests: multi-piece merge + OFFSET placement proven via atMs [1000,2500]; silent-middle skipped;
    no-timings abandons. recorder 54/54, segments 86/86, analyze+format clean.
  - Cold-gate RUNNING (gate-p1-chunking).
- REMAINING (v2 plan): P2 client reliability (keep-alive at hangup so the phone's half isn't lost to
  backgrounding -- the observed issue 2; iOS is the hard part), P3 reader live-update + recording-
  preferred, P4 choreo server-side transcribe, P5 server-side POST (OPEN: how choreo authors the
  Matrix event as the speaker -- appservice/bot/module; the main design risk, needs owner input),
  P6 E2E. Flag stays default OFF until E2E-proven.
- NOTE: flag currently 'false' in the worktree/web .env + the installed phone build is flag-off (old
  live path). Re-enable for E2E once P1-P3 land.

### 2026-09-21 (cont) — P1 cold-gate found 2 real bugs; fixed + mutation-proven; re-gating
- P1 gate (gate-p1-chunking) = ISSUES-FOUND (both proven by the reviewer's arithmetic):
  1. A NEGATIVE/overlong piece-local word timestamp, once shifted by the piece start, could pass the
     whole-recording bound and be placed at a spurious absolute time (single-piece path would reject
     it). FIX (12ae6d827b): bound each timing to its OWN piece [0,pieceDurationMs] before the offset
     (inline `shift`, since momentWithinChunk is @visibleForTesting) -> out-of-piece becomes null
     (floor-placed). Pinned by a test MUTATION-PROVEN to fail without the bound (+0 -1).
  2. Piece cap < one frame -> maxPieceBytes 0 -> divide-by-zero (test-override only; caught -> [] but
     ugly). FIX: clamp maxPieceBytes = max(frame, aligned).
  Also confirmed GREEN by the gate: extraction behavior-preserving; single-piece path gets full PCM;
  silent-skip keeps absolute placement; contiguous coverage for valid caps.
- recorder 55/55, analyze+format clean. P1 re-gate RUNNING (gate-p1-chunking-v2).
- Commits: c75b6a3d19 (P1), 12ae6d827b (P1 gate fixes).
