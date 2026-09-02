# Call end-to-end harness

Drives two real browsers -- and, for some scenarios, a real Android phone --
against a local stack, and asserts what BOTH participants end up with. It
exists because unit tests and code review are structurally blind to the two
things that kept breaking: what a SECOND client sees, and whether a whole flow
works.

## What you need installed

| | |
|---|---|
| Node 18 or newer | `matrix.js` calls the client-server API through the global `fetch`. |
| Google Chrome | A real install. puppeteer-core ships no browser; `CHROME` points at a different one, and `browser.js` fails immediately with that message if the path does not exist. |
| `puppeteer-core` | `cd client/test/e2e && npm install`. It is declared in this folder's `package.json`, so the install lands in `test/e2e/node_modules`. |
| `adb` | Only for the `device_*.js` scenarios. Found via `ADB`, then `ANDROID_HOME` / `ANDROID_SDK_ROOT`, then the usual SDK locations, then `PATH`. |

## What has to be running

A local stack with the two test accounts on it, and the web build being served:

    cd client
    flutter build web --release && cp .env build/web/.env
    python3 ../local-dev/spa_server.py build/web 8091

**Run those from the worktree you are testing.** Before it opens a browser, the
harness fetches `main.dart.js` and `flutter_bootstrap.js` from `APP_URL` and
compares them byte for byte against this worktree's `build/web`; a mismatch ends
the run before any check is asked. This is not defensive tidiness -- servers on
8090 and 8091 were once left running against a DIFFERENT worktree's build, and a
run against them tests code nobody is looking at: green proves nothing, and red
sends somebody to debug a product that was never loaded. A version string cannot
catch it, since two worktrees of one branch share one.

What that gate does NOT settle: whether `build/web` is current with `lib/`. A
bundle built an hour ago from this worktree passes, because it IS this
worktree's build -- running `flutter build web --release` before the suite is
still your step, and nothing here can stand in for it. Nor does it cover
`/.env`, which the app fetches at runtime and which is configuration, not code.

The harness expects, on that stack:

- Synapse answering at `PROBE_HS` (default `http://localhost:8008`).
- The app served at `APP_URL` (default `http://localhost:8091`), from THIS
  worktree's `build/web` -- see above.
- Two accounts, `learner` and `calltester`, that already exist and already
  share a room. `transcript_two_devices.js` signs `learner` in TWICE, in two
  Chrome profiles -- one account, two Matrix devices -- and needs a third wav
  so the two devices do not say the same thing.
- `CALL_ROOM` naming that room's localpart. The default,
  `!HgavfyvZrMpYhLFMLt`, is a fixture of one local stack, not a constant of
  the product -- a stack seeded differently sets its own.

`config.js` holds every one of these, and nothing else in the folder hardcodes
them:

| Variable | Default | What it is |
|---|---|---|
| `APP_URL` | `http://localhost:8091` | where the web build is served |
| `PROBE_HS` | `http://localhost:8008` | the homeserver the assertions read |
| `CALL_SERVER_NAME` | `pangea.localhost` | appended to the room localpart |
| `CALL_ROOM` | `!HgavfyvZrMpYhLFMLt` | the room the two accounts share |
| `CALL_LEARNER_USER` / `CALL_LEARNER_PASS` | `learner` / `learnerpass` | the caller |
| `CALL_CALLTESTER_USER` / `CALL_CALLTESTER_PASS` | `calltester` / `calltesterpass` | the callee |
| `CALL_WORK_DIR` | `$TMPDIR/callweb` | Chrome profiles and fake-microphone audio |
| `CALL_SHOT_DIR` | `$CALL_WORK_DIR/shots` | every screenshot and captured log |
| `CALL_CALLER_WAV` / `CALL_CALLEE_WAV` | `$CALL_WORK_DIR/caller.wav`, `callee.wav` | what the fake microphones play |
| `CALL_LEARNER_ONE_WAV` / `CALL_LEARNER_TWO_WAV` | `$CALL_WORK_DIR/learner_one.wav`, `learner_two.wav` | what the learner's two devices play (`transcript_two_devices.js` only) |
| `CHROME` | the macOS app bundle path | the browser to drive |
| `PHONE_SERIAL` | *none -- throws* | which phone (`adb devices`) |
| `PHONE_PKG` | `com.talktolearn.chat` | add the suffix if your build carries one |
| `ADB` | resolved from the SDK, else `PATH` | the adb binary |

The wav files are optional: without them Chrome uses a generated tone and says
so once. Point them at real speech before judging anything that transcribes a
call. `caller.wav` and `callee.wav` are in `fixtures/`; the learner's two are
not, and `transcript_two_devices.js` refuses to start without them rather than
running two devices on one file, which is the fixture mistake that would make its
central check pass while the feature was broken.

That refusal compares the two wavs BYTE for byte and can see nothing else -- a
second wav of different bytes carrying the same sentences would pass it -- so the
run also checks the OUTCOME: each half has to carry the words of one fixture and
none of the other's, and the half naming the device a browser signs in as has to
carry the wav THAT browser plays. Two things follow for whoever makes these
files. Each wav's distinctive words have to be the ones its side of
`DEVICE_ONE_SAYS` / `DEVICE_TWO_SAYS` lists, and neither wav may contain a word
from the other's list. And each has to run about TWO MINUTES with its sentences
repeated, because Chrome is told `%noloop` and the recording changes hands
mid-call: a fixture that has played to the end hands the device that takes over
silence, and a half with no words in it fails checks that are about the product.
On macOS, for the second device:

    BLOCK='I left the lantern burning by the window all night. [[slnc 900]]
      My bicycle is still chained to the railing outside the front door.
      [[slnc 900]] We walked all the way down to the harbor before the rain
      started. [[slnc 900]] Nothing much has happened around here since
      November. [[slnc 900]] There is cinnamon and walnut in the tin on the
      top shelf. [[slnc 900]] The ferry leaves from the far end of the meadow
      road. [[slnc 900]]'
    say -v Samantha -r 150 -o /tmp/second.aiff "$BLOCK $BLOCK $BLOCK"
    afconvert -f WAVE -d LEI16@48000 -c 1 /tmp/second.aiff \
      "$CALL_WORK_DIR/learner_two.wav"

The block is passed to `say` three times over rather than the file being
concatenated three times: an AIFF header states its own length, so three copies
end to end are not one longer recording.

The first device's wav is made the same way from `DEVICE_ONE_SAYS` -- `compass`,
`orchard`, `trumpet`, `glacier`, `pelican`, `saffron`, `marble`, `thunder` --
into `$CALL_WORK_DIR/learner_one.wav`.

If the words change, `DEVICE_ONE_SAYS` / `DEVICE_TWO_SAYS` in that file change
with them.

## Running

Every scenario is its own process, started from the client root:

    cd client
    node test/e2e/scenarios.js            # the nine-scenario browser suite
    node test/e2e/refresh_midcall.js      # one scenario

`scenarios.js` runs its nine in a fixed order in one process and has no filter;
the standalone files below are the per-scenario entry points. Run them one at
a time: two suites driving the same two accounts fight over the same room, and
the app looks broken ("the call controls never appeared") when in truth another
run just took the room away. `scenarios.js`, `rejoin_ui.js`, `device_four.js`,
`device_redial.js`, `device_rejoin_summary.js` and `device_video.js` refuse to
start while another run is alive; the rest do not check yet.

`transcript_two_devices.js` needs both learner fixtures and, on a machine whose
device ids land the wrong way round, a say-so about which device leaves at the
handover:

    cd client
    CALL_LEARNER_ONE_WAV=$CALL_WORK_DIR/learner_one.wav \
    CALL_LEARNER_TWO_WAV=$CALL_WORK_DIR/learner_two.wav \
    CALL_HANDOVER_DEVICE=one \
      node test/e2e/transcript_two_devices.js

Both wav paths are the defaults, so they can be left out once the files are
there. `CALL_HANDOVER_DEVICE` is an OVERRIDE and is not normally needed: the run
works out which device holds the recording by itself -- `CaptureElection` gives
it to the lower device id, and the scenario pairs each browser with its Matrix
device (see below) -- and hangs that one up, so speech lands in both halves by
construction rather than by luck. Set it only to force the other device. A run
that ends with one half empty FAILS on `BOTH of the learner devices
transcribed`, naming this knob; it does not quietly report the merge check as
inconclusive, which is what it used to do. Hanging up the wrong device also
fails `the device that stayed says it took the recording over`, since no
election flips when the device that was already standing aside leaves.

The whole browser set, sequentially, stopping at the first failure:

    cd client
    for s in refresh_no_return scenarios refresh_midcall rejoin_ui grey_hover; do
      node test/e2e/$s.js || break
    done

Screenshots, captured logcat, and failure evidence all land in
`$CALL_SHOT_DIR`; the scenarios print the path they wrote.

Each scenario prints a summary with three columns -- PASS, FAIL, and SKIP, the
last for a check that could not be asked at all this run. **A SKIP is not a
pass**, and every scenario's exit code says so: `h.report()` returns every
result that is not a pass and sets a non-zero exit code itself, so a run whose
only statement about its central claim stood aside is red. That used to be
arithmetic one scenario kept for itself, which meant the rest exited 0 on a
skip -- and the nine files that call `report()` without reading its return
value exited 0 on FAILURES too.

Two Chrome profiles are reused between runs, so a login survives. A stale one
is the usual cause of "browser is already running"; `unstick.js` (below) is
for the other stale-profile failure, where a profile is parked in onboarding.

## The scenarios

Browser only:

| File | What it proves |
|---|---|
| `scenarios.js` | Nine flows, every action proven on the server and both timelines diffed: answer/hangup, decline, immediate redial, nobody answers, video call answered, quick reply (message + decline, and the caller receives the text), caller gives up, callee reloads while ringing and can still answer, and glare (both call at the same moment -> exactly one card). |
| `refresh_midcall.js` | A mid-call refresh, both sides of it: the surviving side holds the vanished peer's place, the refreshed side is offered its call back, the Return works, the call resumes, no re-ring, one card. |
| `refresh_no_return.js` | The same grace when the peer never comes back: reconnecting is shown, the grace lapses, the survivor ends the call itself, and it is written as a call that HAPPENED rather than a miss. |
| `rejoin_ui.js` | The four review fixes browser-to-browser: a rejoined clock continues rather than restarting, nothing still claims "reconnecting" after the other side ends, the Return banner's red end ends the call for both, and the chat list previews the call. |
| `grey_hover.js` | The CanvasKit grey box: hovers every control on a live ring and fails if a large flat grey block appears that was not there before. |
| `transcript.js` | What the two people can READ afterwards: the consent notice, each speaker's own words under their own name, and turn positions on the wire. Whether the screen wrongly calls a speaker silent is NOT checked -- that prose is drawn by CanvasKit and reaches neither tree, so it is read off the screenshot by eye. |
| `transcript_two_devices.js` | ONE account signed in TWICE in one call. Both devices write TWO distinct halves, the halves name different devices, each half carries the fixture its own browser played and the transaction id that browser was SEEN sending for THIS call (read off its own outgoing requests, scoped by the call key inside them -- see below), the device that stays says in its own log that it took the recording over, the reader says it assembled the account's half from both, and the panel draws at least as many turns as the halves carry. It also refuses a call whose key an earlier call used -- searching back to the event that IS the key, and comparing the keys of every ring the run itself placed -- see below. It does NOT claim to know when any device left the call, or how much of the tail the survivor recorded; neither is observable here. |

Physical Android phone required (all of these; each needs `PHONE_SERIAL`):

| File | What it proves |
|---|---|
| `device_smoke.js` | The standing laptop-to-phone scenario: the phone answers, 55 seconds of talk crosses the 45s chunk boundary, and the evidence is the call card plus the phone's own capture log. |
| `device_p4.js` | The call survives the app leaving the screen: foreground service up with its ongoing-call notification, sixty seconds off screen, back, then hung up from the global call tile, and the service and notification go. |
| `device_notif_action.js` | The ongoing-call notification's own Hang Up, driven from the real shade and proven by the membership going away. |
| `device_redial.js` | A redial the instant after hanging up keeps its own foreground service and notification, and survives 25s backgrounded -- the stop of the previous call must not tear down the new one. |
| `device_video.js` | A video call, and the camera toggle adding and removing the CAMERA foreground-service type for THIS call. |
| `device_rejoin_ui.js` | The four review fixes with the phone as the rejoining side: its app is killed and relaunched, which is what a refresh is to a browser. |
| `device_four.js` | The same rejoin judged only by things that cannot lie -- the server for what happened, screenshots for what was on screen -- plus ending the call from the phone ending it for the laptop too. |
| `device_rejoin_summary.js` | After a return, the summary must report the length of the CALL, not of the segment since returning. Twelve frames of the summary are kept, and read by eye. |
| `device_ui.js` | Two things only a picture settles: the peer's mute badge on their avatar, and the moment after a call. |
| `device_summary.js` | The ended-call summary caught in its three-second window without a blind tap: the laptop hangs up, the phone's grace lapses, and the screen is sampled right through it. |

Not a scenario:

| File | |
|---|---|
| `unstick.js` | A tool. Walks a profile out of the onboarding wizard and proves the room opens afterwards. `node test/e2e/unstick.js calltester`. |

## Known flakiness, and what the files do about it

- **`refresh_no_return.js`'s prelude.** Placing and answering the call before
  the kill can flake (router drift, a click racing a rebuild). The file
  retries the prelude once and checks it separately, so a flaky prelude
  reports as a flaky prelude rather than as a broken grace.
- **Scenario 8, callee reloads while ringing.** A ring lives 30 seconds and a
  reload costs most of it. If the ring expires during the reload itself the
  scenario prints INCONCLUSIVE and skips the answered-card check, because a
  product that correctly refuses an EXPIRED ring must not be recorded as one
  that refuses a REPLAYED one.
- **The first card of a run.** A card is written the moment a call's fate is
  decided but still has to reach the server and come back down sync. Reading
  once failed about half the time on the FIRST scenario of a run -- the one
  also doing its initial sync -- so `assertSymmetric` polls for it.
- **Reading the phone's screen.** A Flutter app only publishes its
  accessibility tree once something asks for it, and the first uiautomator
  dump after a relaunch routinely comes back empty; `device_rejoin_ui.js`
  retries. The app's home animates continuously, so the dump never reaches
  idle there at all -- `device_four.js` and `device_rejoin_summary.js` use
  screenshots instead and are read by eye.
- **Two devices of one account in one call is a RACE, and the race is lost
  more often than it is won.** `answeredOnAnotherDevice` dismisses the second
  device's prompt as soon as the first device's membership lands, so there is
  no way in for a device that answers even a second late.
  `transcript_two_devices.js` therefore fires both taps together and, when only
  one gets in, tears the call all the way down and places it again -- up to
  four times. Three attempts to win it once is normal.
- **The call membership state under-reports during that race.**
  `com.famedly.call.member` is ONE state event per account holding a list of
  that account's devices, and two devices answering in the same instant each
  write the whole list from their own view -- so the later write can drop the
  earlier device. Measured: two events seven milliseconds apart, each naming
  only its own writer, while both devices really were in the call and both
  wrote a transcript half for it. The scenario reads the UNION over the
  timeline rather than the current state for that reason, and anything else
  asking "is the second device in the call" needs the same care.
- **The transcript panel's WORDS cannot be read from the DOM.** It is drawn by
  CanvasKit, and measured here: with six sentences plainly on screen, neither
  `document.body.innerText` nor any `flt-semantics` name carried one of them.
  What DOES reach the tree is each turn's timestamp and each speaker's name, and
  all of them -- Flutter does not clip semantics to a scroll view, so a turn
  below the fold is still there. So a check about the transcript's CONTENT is
  written on the turn COUNT (`transcript_two_devices.js`) or read off a
  screenshot by eye, the way the phone scenarios already do. A check written on
  the words can only ever fail, and one written on their absence -- "nobody who
  spoke is reported as silent" -- can only ever pass. `transcript.js` had the
  second of those and it is gone: a note recording that a check cannot fail does
  not make it honest, it leaves a green line that means nothing. Whether a
  speaker is wrongly called silent is read off `transcript-screen.png` by eye,
  the way the phone scenarios work. A count cannot match a drawn turn to a written one
  either, only their numbers, so the check in `transcript_two_devices.js` is
  named for the floor it establishes -- the panel drew at least as many turns as
  the halves carry -- rather than for the per-turn claim it cannot reach.
- **A drawn-turn count cannot prove a MERGE on its own.** It catches a reader
  that dropped a half with turns in it; it cannot catch one that dropped an
  EMPTY half, because both draw the same screen -- and an empty half is the
  ordinary outcome, since `CaptureElection` lets only one of an account's
  devices record. So `transcript_two_devices.js` proves the merge off the app's
  own read-time log instead, which states how many devices a half was assembled
  from (`... devices 2`) and is written unconditionally for any half assembled
  from more than one. The turn count is still asked every run, and a run that
  did not reach two speaking halves FAILS rather than standing the count aside:
  a scenario that could not reach the state it tests has not passed.
- **A membership read answers one of its two questions.** A device PRESENT in
  `com.famedly.call.member` really is in the call -- nothing invents a sibling --
  so a check that refuses on presence is on solid ground. A state that reads
  EMPTY is one writer's view, and the product means it to be, so nothing may
  conclude a device has LEFT from it. Three checks in
  `transcript_two_devices.js` did: two about the handover, and later two about
  the hangups at the end of the call, which passed when a survivor's click
  missed and the state omitted it anyway. All are gone. What a departure was
  really being asked for -- did this participant's call end, so that its half
  gets written -- is answered by the half ARRIVING, which is presence, and which
  the run already requires three times over. If you write a new scenario, grep
  it for every membership read before you trust one: the finding names one site
  and the class is what needs fixing.
- **A fixed sleep proves nothing about a drain of unbounded length.** The retry
  loop tears an abandoned attempt down and waits ten seconds before racing
  again, which makes a reused call key less likely and says nothing about
  whether one happened -- the abandoned call's half can land long afterwards,
  under the same key, and be read as part of the winning call. The room search
  cannot see it while it is still draining. What settles it is that the harness
  watched both rings: every attempt's call key is remembered, and a winning key
  an earlier attempt already rang with is a reuse observed rather than inferred.
  The scenario fails on it rather than proceeding -- a run that manufactured the
  bug it exists to detect is not a green run.
- **Nothing in this stack witnesses the MOMENT a device left a call.** The
  membership state is one event per account written by whichever device wrote
  last, holding that writer's view of the roster -- so a device's absence from
  it is an opinion, and the product means it to be (see the under-reporting note
  above). A transcript half arrives after a drain of no fixed length, so it
  cannot date the leave it followed. And the harness's own hangup click is a
  request, not a departure. Two checks in `transcript_two_devices.js` were
  written on that instant and each rewrite reached for a different proxy for it;
  every proxy had a sequence that defeated it, which is the tell that the
  problem was the claim rather than the measurement. Both are deleted. What is
  asked instead is what the surviving device SAYS: `ActiveCall` logs "Recording
  this call on this device" when the election flips it into recording, guarded
  on the state actually changing and printed after reading the recorder back, so
  the device the handover is for announces it from the roster it can see. Scope
  any such search by position in the page's own log -- the device holding the
  recording says the same sentence at the join.
- **How much of a tail was recorded cannot be read off a half.** `PcmChunker`
  targets 45-second chunks, so the 40-second stretch after the handover is ONE
  chunk and its segment positions sit at its start. Nothing separates a survivor
  that recorded two seconds from one that recorded forty, and `chunks_captured`
  is worse than useless for it: a device that is standing aside still captures
  and discards, so the count includes audio it threw away.
- **A crossing test is only as good as the words it is written on.** The
  cross-account check looks for `PEER_SAYS` under the learner; if the peer's wav
  changed, or speech-to-text missed those sentinels while catching other words,
  the search runs over words nobody spoke and comes back empty for a reason that
  has nothing to do with the product -- while a merge that put the peer's REAL
  words under the learner goes unnoticed. The peer's own half has to carry the
  sentinels before their absence elsewhere means anything. The same applies to
  any fixture-word check: verify the detector against the half that should
  contain it first.
- **A transaction id exists only in the request that carried it.** Matrix
  returns `unsigned.transaction_id` to the sending DEVICE's own sync and to
  nobody else, and the harness holds a different device's token -- so the id a
  send used cannot be read back off the room. Recomputing it from the event that
  arrived proves the event carries enough to derive an id, which is a strictly
  weaker sentence: a client regressed to a sender-only key, on a homeserver that
  accepted both devices' requests, lands two events a recomputation derives two
  distinct ids from. `transcript_two_devices.js` therefore wraps `fetch` and
  `XMLHttpRequest` on each learner page before the app loads and reads the id out
  of the PUT path (`.../send/{type}/{txnId}`). Comparing the ids seen against the
  ids derived as SETS gives that observation away again: two sets that match
  prove two valid device ids exist at both ends and nothing about which browser
  sent which, so a build with the two ids swapped over passes. The comparison is
  therefore per browser -- the id this page was seen sending, the arrived half
  the formula derives it from, and that half's device id against the device this
  page's own token belongs to. The same hook lifts the session's
  bearer token, which is the only way to ask which Matrix device a browser is --
  nothing the app puts on the page carries the id, and `/devices` cannot tell two
  Chrome profiles on one laptop apart. Scope the token capture to
  `/_matrix/client/` URLs if you copy this: the app also talks to the
  choreographer with a bearer of its own, and taking whichever went past last
  yields `M_UNKNOWN_TOKEN` and reads as a browser that could not be identified.
- **Deduping a send log hides the thing worth seeing.** Two PUTs under ONE
  transaction id collapse to a single entry, so "this device was seen sending a
  half" can pass on a device seen sending it twice -- and a duplicate send under
  one key is exactly what a reused call key produces, the homeserver answering
  the second from its transaction cache and writing nothing. Count the raw sends
  and assert that, then dedupe for the id comparison.
- **A page's send log outlives the call, so scope it.** The watcher below
  records every transcript PUT a page makes for the life of the process, and the
  retry loop can place and tear down calls before the winning one -- a torn-down
  call writes its halves too. Reading the log unscoped answers "was this device
  seen sending a half" partly out of a call nobody is asking about: a device that
  never wrote a half for the winning call, but had written one for an abandoned
  attempt, reads as a device seen sending exactly one. The scope needs nothing
  marked browser-side, because the send declares its own call -- the call key is
  a field of the transaction id, in the PUT path -- so it is the exact
  counterpart of `content.call_key` on the events. Match it as a PREFIX: a user
  id and a v1 event id both contain colons, so splitting the id on them is
  ambiguous.
- **A "since this mark" read widens silently when the mark ages out.** The
  harness's `since` pulls a window of the timeline, finds the marker and returns
  what follows -- and when the marker is no longer in the window it returns the
  WHOLE window instead. Every caller means "what happened since I marked", and
  the fallback quietly answers "the last N events": a wider set, in the
  permissive direction, with nothing to show the question changed. In
  `transcript_two_devices.js` that reached far -- the ring lookup would take an
  abandoned attempt's ring and scope the entire run to the wrong call key -- so
  that file reads through its own `sinceScoped`, which throws instead. Worth the
  same care anywhere else a scenario marks and reads back.
- **Clearing a cache does not fix the wrong build.** `openParticipant` purges
  the Flutter service worker from each Chrome profile, which handles a browser
  serving a build it cached earlier. It does nothing about the bundle on the
  SERVER being another branch's, and the two look identical from inside a run.
  The only thing that separates two worktrees is the bundle's BYTES: a stamp
  answers "what does this build say it is", and two worktrees of one branch say
  the same thing. So the gate compares the served bytes against `build/web` in
  the worktree the harness file itself is running from -- an anchor taken from
  `__dirname` rather than from a setting, because an identity read out of
  configuration is satisfied by whatever the configuration points at.
- **A Chrome profile's login is per ORIGIN.** Serving a second build on another
  port and pointing `APP_URL` at it does not reuse the session: the profile
  signs in again and Synapse mints NEW devices. Fine, and worth knowing before
  reading two runs against two ports as if the device ids were comparable.
- **Phone tap positions are calibrated to one device** (960x2142), in
  `device.js`'s `BANNER` and `TAP` tables. On another handset they miss --
  and because every tap is followed by a server-side check, that shows up as
  a clean failure plus a screenshot to recalibrate from, not as a pass.

## The rules it is built on

**Assert from the server, never from the canvas.** `matrix.js` logs in as both
accounts over the client-server API, reads both timelines, parses the call
cards with the same direction logic the UI uses, and diffs them. A room is
shared, so a row one participant has and the other does not is by definition a
bug -- that check is what found the ghost-card bug, where a failed send left a
card in one client's local timeline for ever.

**Navigate by URL, and prove it worked.** `harness.openRoom` goes to
`/?left=chats,room:<localpart>` and then waits for a control that only exists
inside a chat, retrying -- clearing the route, then clicking the conversation
in the chat list the way a person would -- and finally throwing. The app can
resolve its own route after login and land back on the activity map; without
the check the harness would drive the map and report nothing.

**Never let a missed click look like a pass.** The harness this replaced
clicked fixed points like (680,126), and rotted silently: after a layout change
it clicked empty space and still "passed" a flow it was no longer exercising.
The login did the same thing -- six fixed coordinates and a macOS-only
select-all -- and `login.js` now reads the screen instead, finding the form's
own inputs and finishing only when the form is gone.

Flutter's accessibility tree covers only part of this app: the chat header's
call buttons are reachable by label, but the ring banner and the in-call panel
are NOT in the tree at all (verified by dumping every `flt-semantics` node
while a ring was on screen and confirming against a screenshot that the banner
was plainly visible with none of its controls represented). Those are clicked
by position -- and EVERY such click is followed by a server-side assertion that
the action actually happened: answering must produce a call membership,
declining must produce a decline event, hanging up must remove the membership.

**Reload through `harness.wake`, never by hand.** Flutter web only publishes a
semantics tree once its placeholder has been clicked, and a reload throws that
away with the rest of the document. A scenario that reloads and then reads text
sees an empty page for ever and reports the product broken.

**Reload between scenarios** (`harness.recover`). With semantics enabled, the
Flutter web engine's semantics click pipeline does not reliably survive a call
panel's teardown -- later clicks die inside the engine's ClickDebouncer with a
null-state error before any app code runs. Verified semantics-specific: the
same flows driven by raw coordinates with semantics off work, which is why
ordinary users never see it. Real users of assistive technology WOULD -- filed
as a known accessibility issue rather than fixed here, because the corruption
is inside the engine.

## What it has already caught

- A call card whose send failed staying in one client's local timeline for ever
  (fixed, 3cefe105a2) -- found by diffing both participants' timelines.
- Every ring transaction id being sent TWICE, the second silently swallowed by
  the homeserver's dedup so the callee never rang (fixed, 70eb5a2a8b) -- found
  because the caller showed "Ringing..." while the server's access log showed
  the ring PUT returning 200 with [0 dbevts].
- A regression introduced WHILE fixing the above: a guard added to startCall
  caused a null dereference that stopped the second call in a session from
  placing at all. Caught here and reverted (175e32c51b) before it could ship,
  and fixed properly in c784e7c5d6.
- **A whole call's transcript destroyed by a reused call key.** A redial two
  seconds after a hangup rang with the PREVIOUS call's membership event id, so
  both calls shared a `call_key`. The transcript transaction id is
  `(call key, sender, device)`, and this homeserver collapses a repeated
  transaction id from the same device -- so every writer in the second call
  recomputed an id it had already used, the server handed back the earlier
  event, and forty-eight seconds of conversation reached the room as nothing at
  all, with no error logged anywhere. The second call's CARD landed, sharing the
  first's key, so the renderer's first-per-key rule drew a 48-second call as an
  11.8-second one. `transcript_two_devices.js` refuses a call whose key an
  earlier half already used, which is what turned this from silence into a
  failure. The search walks the room back to the event that IS the key -- a call
  key is the caller's own membership event id, and nothing can have been written
  under a key before it -- rather than reading a fixed window. A window answers
  "no earlier half in the last N events", which is a different sentence from the
  one the check is named for, and a run that cannot reach the boundary reports
  an unfinished search rather than a clean call. The room search is not the
  whole of it either: an abandoned attempt's half drains on no schedule, so a
  key reused between two attempts of ONE run is invisible to it until that half
  lands -- by which time the two calls' halves are in the room under one key and
  read as a single call. The keys of every ring the run places are compared as
  well, which catches that at the moment it happens.
- **A call that stops being recorded when one of an account's devices leaves.**
  Two of the learner's devices in one call; the one holding the recording hung
  up at thirty-five seconds; the survivor held the call alone for another forty
  and captured NOTHING -- zero chunks, no refusal, no loss, nothing dropped.
  Reproduced on two runs. The election is supposed to re-run on the roster
  change and hand the recording to the survivor. Read the caveat the check
  itself prints before acting on it: this stack's LiveKit token lacks
  `CanUpdateOwnMetadata`, so the capability layer the election leans on is dead
  here and the app says so in its own log on every run -- which is either the
  cause or the thing that has to be ruled out first. What catches it now is the
  surviving device's OWN log line -- `ActiveCall` says "Recording this call on
  this device" when the election flips it into recording -- plus the three
  checks that read the halves: both carrying words, each carrying its own
  fixture, and the reader assembling from two devices. A survivor that recorded
  nothing fails all four.
