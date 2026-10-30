# Route suite checkpoint (2026-10-22, paused on owner request)

## Built

- `test/e2e/routes/`: 16 browser routes (r01-r15, r05 at 75 s and 150 s),
  `lib.js` (shared criteria), `standard.js`, `switch.js`, `run_all.sh`
  (one route at a time, results table, `ROUTES_TABLE_ONLY=1`),
  `setup_local.js` (routes_es / routes_fr accounts + DM rooms),
  `make_fixtures.sh` (TTS fixtures + noisy variants), and
  `sim_ipad_voice.js` (simulator leg, not run yet).
- Codex honesty gates: 4 rounds, last verdict ISSUES-FOUND with
  GATE-SOFTENING: no; every finding since round 1 fixed or listed under
  "Known limits" in README.md. One round-1 finding (eventsSince page order)
  was wrong and its "fix" was reverted.

## Baseline results so far (evidence under `$ROUTES_OUT/<variant>/<route>/`)

Variant a = client origin/main 1bd5c2b987 + choreo origin/main ff3b5c9d.
Only r08 (missed) passes. Recurrent failures: no punctuation on Whisper
halves (r01, r03, r06, r13-r15); r02 throttled: STT/uploads time out at the
client's 30/60 s bounds, no recordings, no peer half, no loading state;
r04 web kill during upload loses the callee's recording and half (web keeps
pending recordings in memory only); r05a/b: device two joins mid-call and
leaves seconds later, no prompt (#9173 mechanism); r07: busy shows as plain
"Call declined", no "is on another call", no busy tone; r09: no two-device
prompt on either device; r10: recording-based pass fails on an 85 s call
(choreo TokenRequest full_text > 1000 chars, then Google sync > 1 min), so
the unsubscribed peer's half is never produced; r11/r12: lock shown, no
#8791 sentence (conflicts with the design doc's lock-only rule); r14/r15:
L1 English sentences dropped (#3351).

Variant b as specified (choreo stt-3351-allow-l1 merged with choreo main):
NOT RUN, the merge conflicts in speech_to_text.py and
speech_to_text_schema.py (expected-text hint, #3391).
Variant b' (client main + 9173-switch-fix + 3351-allow-l1, choreo main),
subset: r05a and r05b move the call correctly (both stretches, links, one
complete merge, clock in sync, credit once); r09 passes except punctuation;
r14 unchanged (needs the choreo half).

iOS / iPad Simulator: NOT RUN. `flutter build ios --simulator` fails
("No such module 'receive_sharing_intent'": the Podfile excludes arm64 for
simulator pods on an Apple Silicon Mac); an x86_64 xcodebuild fails in
rive_native's "Rive Native Compile" phase. No virtual audio device is
installed; the plan was afplay through the Mac speakers into the Mac mic.

## STT spend so far

About $0.68 measured client-side (Whisper list price), plus up to about
$0.10 for choreo-internal Deepgram fallback attempts after the TokenRequest
failures: about $0.78 of the $1 cap.

## Next

1. Get a simulator build (owner decision: local Podfile/arch tweak, or a
   prebuilt simulator .app), then run `sim_ipad_voice.js` on an iPad
   (routes_fr, #3382) and an iPhone simulator, one at a time.
2. Optional, budget permitting: re-run b' r05a with the newer prompt
   detection; resolve the choreo conflict only if the owner wants variant b.

## Resume

    open -a OrbStack; open -a Docker
    docker --context orbstack start pangea-synapse-local pangea-livekit-local pangea-fedtls-local pangea-lk-jwt-local
    docker --context desktop-linux start cms-postgres-1
    (cd ~/PangeaChat/cms && PATH=$HOME/.nvm/versions/node/v26.3.0/bin:$PATH pnpm dev)   # :13134
    ~/PangeaChat/tmp/routes-run/start_choreo.sh ~/PangeaChat/choreo-routes-main         # :8012, subscription required
    cd ~/PangeaChat/client-routes
    PATH=$HOME/fvm/versions/3.41.4/bin:$PATH flutter build web --release && cp .env build/web/.env
    python3 ../local-dev/spa_server.py build/web 8091 &
    export CALL_WORK_DIR=~/PangeaChat/tmp/routes-run/work ROUTES_OUT=~/PangeaChat/tmp/routes-run/out
    ROUTES_VARIANT=a-main test/e2e/routes/run_all.sh [route ...]
    ROUTES_VARIANT=a-main ROUTES_TABLE_ONLY=1 test/e2e/routes/run_all.sh <routes>   # table only

`start_choreo.sh` reads a local-only CMS service key from
`~/PangeaChat/tmp/routes-run/.cms_key` (minted on the local CMS). Variant b'
runs from `~/PangeaChat/client-routes-integ` (local branch
satvik/routes-integ-client, never pushed) after rebuilding its web bundle.
