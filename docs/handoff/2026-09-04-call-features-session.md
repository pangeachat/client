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
  or manual). OPEN PROD RISK: staging LiveKit version unknown from checked-out
  repos (Ansible-deployed) -- if too old for the protocol-16 attribute ack, the
  dual-device election is broken in prod too (every 2-device call duplicates).
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
