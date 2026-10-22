# Call route suite

The local counterpart of QA's call-transcription sweep
(pangeachat/2-step-choreographer#3350). One file per route; each drives real
browsers against the LOCAL stack and asserts the #3350 pass criteria from the
server (room events, the saved media, the analytics room) and from the Flutter
semantics tree. A check that cannot be asked is a SKIP, and a SKIP is not a
pass: a route exits 0 only when every check it asked passed.

## Routes

| File | #3350 route | Call | Subscription | Network / event |
|---|---|---|---|---|
| r01_voice_both_good | 1 | voice | both | good |
| r02_voice_one_throttled | 2 | voice | one | both browsers throttled through the call and the upload |
| r03_video_both_good | 3 | video | both | good |
| r04_voice_both_dropend_kill | 4 | voice | both | callee offline at call end, app SIGKILLed during upload, reopened |
| r05a / r05b_voice_both_switch75/150 | 5 | voice | both | learner switches device ("Use this device") at ~75 s / ~150 s |
| r06_voice_one_good | 6 | voice | one | good |
| r07_voice_decline_busy | 7 | voice | one | decline, then busy (callee already on another call) |
| r08_voice_missed | 8 | voice | one | rings out |
| r09_video_both_second_device | 9 | video | both | same call opened on a 2nd device, "Leave the call here" |
| r10_video_one_dropmid | 10 | video | one | callee offline 20 s mid-call |
| r11_voice_neither / r12_video_neither | 11 / 12 | voice / video | neither | good |
| r13_voice_both_noisy | acoustic | voice | both | noise + music under both voices (#3356) |
| r14_voice_es_l1l2 / r15_voice_fr_l1l2 | language | voice | both | en->es / en->fr learner speaking L2 and L1 (#3351, #3382) |

What each asserts, where it applies: the recording notice; a loading state on
the transcript screen right after the call (#8808); each person's turns under
their own name when anyone is subscribed (#8792); punctuation (#9303); a saved
recording from both people and ONE complete full-call recording that decodes,
has sound and is about the call's length; credit counted exactly once in the
analytics room (#9302); the lock / "no transcript" text for the unsubscribed;
after a switch both stretches, the `handed_over_to` / `continued_from` links,
one complete merge and a clock that agrees with the peer's (#9173, #8878).

## Limits, stated so a green line is not read as more than it is

- DevTools network emulation governs HTTP and websockets (sync, uploads,
  choreo, the LiveKit signal socket). It does NOT throttle or cut WebRTC
  media. "Throttled" and "offline" here are about the control plane and the
  uploads, not call audio quality.
- The transcript panel's prose is drawn by CanvasKit; checks on it read the
  semantics labels, and a label that is not in the tree makes the check SKIP.
- Credit is read from the speaker's analytics room. The analytics service
  sends on its own schedule; uses that never arrive within the wait are a SKIP.
- Real speech-to-text runs for every subscribed route. Watch the spend.

## Running

    cd client
    export CALL_WORK_DIR=<persistent scratch dir>
    node test/e2e/routes/setup_local.js          # es/fr accounts + rooms (once)
    test/e2e/routes/make_fixtures.sh             # wav fixtures (once)
    ROUTES_OUT=<dir> ROUTES_VARIANT=main test/e2e/routes/run_all.sh [route ...]

Needs: the local stack incl. lk-jwt; this worktree's `build/web` served at
`APP_URL` (`python3 ../local-dev/spa_server.py build/web 8091`); choreo on
`CHOREO_URL` started with `CHOREO_REQUIRE_SUBSCRIPTION=true` and a local CMS
whose Postgres container is `ROUTES_CMS_PG` (default `cms-postgres-1`, docker
context `ROUTES_CMS_PG_CONTEXT`, default `desktop-linux`). Subscriptions are
set per route by writing one `manual:routes:<user>` entitlement row in that
LOCAL database and are confirmed through choreo's `/subscription/status`
before the call. `run_all.sh` runs routes one at a time and kills every suite
Chrome between them.

## Known limits of the assertions (accepted, not hidden)

- **Which call a transcript screen shows.** The newest card's transcript is
  opened (the lowest link), and tied to this call by the full-call length shown
  on its player. An older call of the same length whose card sits lower could
  in principle stand in; the route also requires exactly one new card.
- **Credit counted once.** Call construct uses carry no id on the wire, so a
  double credit is detected as a second credit moment, every use doubled, or an
  analytics event repeated exactly. A partial re-send of some uses inside
  differently split events would not be seen.
