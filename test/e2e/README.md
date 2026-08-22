# Call end-to-end harness

Drives two real browsers against the local stack and asserts what BOTH
participants end up with. It exists because unit tests and code review are
structurally blind to the two things that kept breaking: what a SECOND client
sees, and whether a whole flow works.

## Running

Needs the local stack up, a web build served, and puppeteer-core.

    cd client && flutter build web --release && cp .env build/web/.env
    python3 ../local-dev/spa_server.py build/web 8091
    node test/e2e/scenarios.js          # APP_URL / PROBE_HS override the defaults

Two Chrome profiles with fake microphones are reused between runs; a stale one
is the usual cause of "browser is already running".

## The rules it is built on

**Assert from the server, never from the canvas.** `matrix.js` logs in as both
accounts over the client-server API, reads both timelines, parses the call cards
with the same direction logic the UI uses, and diffs them. A room is shared, so a
row one participant has and the other does not is by definition a bug -- that
check is what found the ghost-card bug, where a failed send left a card in one
client's local timeline for ever.

**Navigate by URL, and prove it worked.** `harness.openRoom` goes to
`/?left=chats,room:<localpart>` and then waits for a control that only exists
inside a chat, retrying and finally throwing. The app can resolve its own route
after login and land back on the activity map; without the check the harness
would drive the map and report nothing.

**Never let a missed click look like a pass.** The previous harness clicked fixed
points like (680,126) and rotted silently -- after a layout change it clicked
empty space and still "passed" a flow it was no longer exercising.

Flutter's accessibility tree covers only part of this app: the chat header's
call buttons are reachable by label, but the ring banner and the in-call panel
are NOT in the tree at all (verified by dumping every `flt-semantics` node while
a ring was on screen and confirming against a screenshot that the banner was
plainly visible with none of its controls represented). Those are therefore
clicked by position -- and EVERY such click is followed by a server-side
assertion that the action actually happened: answering must produce a call
membership, declining must produce a decline event, hanging up must remove the
membership. A click that misses fails loudly instead of quietly passing.

## What it has already caught

- A call card whose send failed staying in one client's local timeline for ever
  (fixed, 3cefe105a2) -- found by diffing both participants' timelines.
- Every ring transaction id being sent TWICE, the second silently swallowed by
  the homeserver's dedup so the callee never rang (fixed, 70eb5a2a8b) -- found
  because the caller showed "Ringing..." while the server's access log showed
  the ring PUT returning 200 with [0 dbevts].
- A regression introduced WHILE fixing the above: a guard added to startCall
  caused a null dereference that stopped the second call in a session from
  placing at all. Caught here and reverted (175e32c51b) before it could ship.

## Scenario coverage

Nine scenarios, every action proven on the server, both timelines diffed:
answer/hangup, decline, immediate redial, ring-out (no answer), video call,
quick reply (message + decline + caller receives the text), caller-gives-up,
reload-while-ringing (the D1 replay, answered after a mid-ring reload), and
glare (simultaneous calls -> exactly one card).

Between scenarios both clients RELOAD (`harness.recover`): with semantics
enabled, the Flutter web engine's semantics click pipeline does not reliably
survive a call panel's teardown -- later clicks die inside the engine's
ClickDebouncer with a null-state error before any app code runs. Verified
semantics-specific: the same flows driven by raw coordinates with semantics off
work, which is why ordinary users never see it. Real users of assistive
technology WOULD -- filed as a known accessibility issue rather than fixed here,
because the corruption is inside the engine.

## The phone participant (device.js)

`device.js` adds a REAL Android phone to the harness, driven over adb, with
the same philosophy as the browser side: taps are proven by server outcomes
(membership written, decline sent, audio uploaded), never by pixels alone.
`device_smoke.js` is the standing scenario: the laptop places the call, the
phone answers, 55 seconds of talk crosses the 45s chunk boundary, and the
evidence is the call card plus the phone's own capture log lines.

- `PHONE_SERIAL` / `ADB` env vars point it at a different device or sdk.
- A fingerprint lock cannot be driven from adb. The harness DETECTS the
  keyguard and fails with "ask the user to unlock it" instead of letting
  every later step fail mysteriously. Keep the screen on across installs:
  `adb shell svc power stayon true` plus a periodic KEYCODE_WAKEUP.
- Banner tap positions in `BANNER` are calibrated to one device (960x2142
  render). On a failed outcome the scenario screenshots the phone so the
  calibration is corrected from evidence.

## Refresh scenarios (refresh_midcall.js, refresh_no_return.js)

The mid-call-reload pair. `refresh_midcall` is the flagship: grace on the
surviving side, the Return offer on the reloaded side, tap, resumption
proven by a 25s soak, no re-ring, one card -- stable at 9/9.
`refresh_no_return` proves the grace end-to-end (reconnecting shown, ~20s
grace measured, self-end, answered card): it has run 5/5 green, but its
place-the-call PRELUDE flakes when run back-to-back after other scenarios
(the ring event never reaches the room; the same steps pass standalone).
Run it first, or standalone, until the prelude flake is traced.

## Known gaps

- The former "next call after an answered call places nothing" bug is resolved:
  it was the engine semantics pipeline (see above), plus two real product bugs
  it was masking -- the reused ring transaction id (70eb5a2a8b) and the
  finished-session release window (c784e7c5d6 + the startCall step-over).
- Scenarios still to add: glare, reload while ringing, callee busy, caller
  cancels, second device, video, connect failure.
- Both clients log "Unexpected token '<'" -- something fetches a path that the
  SPA server answers with index.html. Not yet traced.
