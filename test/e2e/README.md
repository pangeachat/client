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

## Known gaps

- OPEN BUG, reproducible: after a call that was ANSWERED, the caller's next call
  places nothing at all -- no membership, no ring -- while the call button sits
  there and the screen stays idle. `scenarios.js` fails on it at
  "placing a call rang the other side". A plain ring-then-hangup call does NOT
  reproduce it, so the answered path leaves something behind. Not yet root
  caused.
- Scenarios still to add: glare, reload while ringing, callee busy, caller
  cancels, second device, video, connect failure.
- Both clients log "Unexpected token '<'" -- something fetches a path that the
  SPA server answers with index.html. Not yet traced.
