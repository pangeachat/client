# Agent QA Checklist — Pangea Chat Web Client

The single **living checklist** for agent-driven, exploratory browser QA of the Flutter web client. Each item is derived from a feature doc (the *oracle*), organized by end-to-end **user journey**, and falsifiable: a cited `Expect` turns "is this a bug?" into a clean yes/no. Regenerate as features ship; turn each found bug into a regression item.

## How to use this

1. **Read [`agent-browser-qa/SKILL.md`](../.github/skills/agent-browser-qa/SKILL.md) first.** It owns the canvas-driving recipe (the map-tile-gated semantics race + wake-and-poll), the single-browser round structure, and the dead-ends that don't work. Do not free-style the canvas.
2. **Pull a round, don't run the whole file.** Take a journey (or a state-matrix slice of one), drop non-web items, paste the items + their `Expect` lines into the agent prompt as the flows to exercise. Prefer several scoped rounds over one open-ended sweep.
3. **Guard the two app-specific false-negatives on every judgment.** (a) Confirm the semantics tree is built before asserting anything is "missing" — an empty / 2-node tree is the load race, not a bug (run the wake-and-poll recipe). (b) Distinguish **gated** (subscription / lock / role) from **missing** before reporting.
4. **Report findings back to the requester** (functional bugs + semantic/a11y gaps), each with screen, repro, expected-vs-actual, severity, screenshot id. **Do NOT file GitHub issues** — the team's flow for QA-found bugs is fix-and-push to staging.
5. **Bypass paid backends** with `mock=true` (+ `mock_llm_latency_override_s=0`) where possible. Respect live-session guardrails: no destructive actions, no real messages to other humans; bot interaction is fine.

### Tag legend

| Tag | Meaning |
|-----|---------|
| `[gated]` | Behind a subscription, progression lock, role/power-level, or other entitlement — confirm the gate, don't report it as missing. |
| `[staging-only]` | Needs live Synapse / RevenueCat / choreographer / seeded data — not reproducible in mock or on a fresh account. |
| `[recently-changed]` | Recently shipped or migrated; higher prior on regressions — test these first. |
| `[flaky]` | Timing-, debounce-, cache-, or LLM-nondeterminism-sensitive — observe-then-settle, assert end state not transitions. |
| `[manual]` | Beyond automated reach (keyboard-only, contrast/zoom, screen-reader announcement) — requires a human pass. |

---

## Cross-cutting invariants (check on every surface)

Apply these to **every** panel, sheet, dialog, and detail you open. They are the cheapest regression catches.

- [ ] **No route exception / blank screen** — every reachable surface renders; no `GoException`, raw error text, or blank canvas at any panel/scope state. _(routing.instructions.md)_
- [ ] **Back & close work and don't orphan state** — back button and panel close (X / back-arrow) leave a coherent state; closing a panel never silently changes map scope; closing a child reveals its master. _(routing.instructions.md)_
- [ ] **Loading / empty / error states render** — never an infinite spinner or unhandled raw error: loading shows shimmer/placeholder, empty offers a next step (e.g. map "widen" affordance, language fallback list), error shows a handled indicator. _(routing.instructions.md; world-map.instructions.md; language-list.instructions.md)_
- [ ] **Semantic / a11y completeness** — every interactive control on the canvas exposes a name + tooltip; no `button [ref]` with no name, no unlabelled icons/images. The map is opaque to a screen reader until explicitly named. _(accessibility.instructions.md; routing.instructions.md)_
- [ ] **Responsive (column vs single)** — above ~833px two-column (nav rail + up to two panels per column over the map); at/below ~833px single-column (rail → bottom nav, one panel shows). Layout adapts cleanly across the breakpoint with no orphaned/overlapping chrome. _(layout.instructions.md; routing.instructions.md)_

---

## Journey 1 — Onboarding & Auth

End-to-end: logged-out chooser → sign-in/up → L2 setup gate → land on the workspace; returning-user recognition.

- [ ] Navigate to `/` while logged out — **Expect:** the login-or-signup chooser at `/home` renders, not the workspace (`roomsRedirect` returns `/home` when not logged in). _(routing.instructions.md; p_vguard.dart)_
- [ ] Navigate to `/` logged in with L2 already set — **Expect:** lands on the world-map workspace (`PRoutes.world`), not `/registration`. _(p_vguard.dart; [gated] [staging-only])_
- [ ] Logged in but L2 NOT set, try to load `/`, `/home`, or `/onboarding` — **Expect:** redirected to `/registration` until an L2 is chosen; the world map is unreachable with no L2. _(p_vguard.dart; [gated] [staging-only])_
- [ ] Reopen login screen after a prior sign-in (keychain hint persisted) — **Expect:** "Welcome back! You previously signed in with {method}" banner; the matching SSO button is emphasized, others de-emphasized but available. Logout does NOT clear the hint. _(returning-user-detection.instructions.md; [returning-user] [flaky] [staging-only])_
- [ ] Open signup screen on a fresh device / cleared keychain — **Expect:** all three options (Google, Apple, email) shown equally, no "welcome back" hint. _(returning-user-detection.instructions.md; [staging-only])_
- [ ] Web caveat: reopen login in same browser, then again after clearing site storage — **Expect:** the "previously signed in" hint is best-effort on web (rides flutter_secure_storage, not iOS Keychain) and may NOT survive a storage clear. _(returning-user-detection.instructions.md; [returning-user] [flaky])_
- [ ] Enter a course code at the onboarding code step — **Expect:** converges on the same `SpaceCodeController.joinSpaceWithCode()` flow as the in-app page and bottom sheet; auto-joins identically. _(joining-courses.instructions.md Route 2)_
- [ ] Pick a target language where the CMS `/api/languages` request is blocked / cache empty — **Expect:** the list still populates from the hardcoded fallback (`LanguageConstants.languageList`); selection never dead-ends. _(language-list.instructions.md)_

---

## Journey 2 — Discover → Join → Activity → Bot → Complete → Progress → Unlock

The spine of the product. The expensive bugs live at these seams (the LO-lock gate, the activity-ended transition). Test the locked/unlocked/joinable branches first.

### 2a. Discover on the map

- [ ] Load `/` with an L2 + CEFR set and located activities in view — **Expect:** map renders full-bleed with no panel open; pins are the personalized default (only my L2, only activities at/below my CEFR, in-viewport, colored by state). _(world-map.instructions.md)_
- [ ] Pan/zoom to a viewport where the personalized-default set is empty — **Expect:** a "widen" affordance (all languages / zoom out) is offered; the map never shows a permanent empty state. _(world-map.instructions.md)_
- [ ] Change one-tap reset after changing L2/CEFR/completion or widening — **Expect:** reset returns to personalized default (my L2, default CEFR band, no completion filter, no query); if L2 had been widened, reset re-narrows to L2 and re-fetches pins. _(world-map.instructions.md)_
- [ ] Toggle a CEFR level off/on with the loaded set unchanged — **Expect:** pins refine in place from the already-loaded set (no re-query); non-matching CEFR pins disappear, matching stay, unknown-level (`cefr==null`) kept. _(world-map.instructions.md)_
- [ ] Change the L2 filter to all-languages / a different language — **Expect:** the working set widens via a re-query (new candidate items appear), not just an in-view unhide. _(world-map.instructions.md)_
- [ ] Type a query in map search and select a result — **Expect:** as-you-type results match title/description/learning-objective; selecting flies the camera to the item and opens its large card. _(world-map.instructions.md; [world-map-search])_
- [ ] Switch app theme light↔dark, observe base tiles — **Expect:** light loads OSM standard raster (`tile.openstreetmap.org`); dark loads CartoDB Dark Matter (`basemaps.cartocdn.com/dark_all`); tiles fetched direct from CDN, never proxied. _(world-map-tiles.instructions.md; [world-map-tiles])_

### 2b. Pin state & progress (the gate)

- [ ] Inspect a locked vs unlocked activity pin in a joined course with a gated LO — **Expect:** locked = gray, unlocked = purple, live joinable session = green; lock resolved client-side (LO unlocks once prior LO has ≥10 stars, teacher-overridable). _(world-map.instructions.md; quests.instructions.md; [gated] [staging-only])_
- [ ] Inspect a first-Mission (always-unlocked) activity pin — **Expect:** purple/unlocked and launchable; `buildLoGate` unlocks index-0 of every sequence unconditionally — a first-Mission activity is never gray. A course with no gated sequence is never locked. _(quests.instructions.md; world-map.instructions.md; lo_progression.dart; [staging-only])_
- [ ] Inspect an activity that is behind the gate BUT has an open joinable session — **Expect:** renders green (joinable), NOT gray; the lock layer is suppressed when joinable, and the ladder `locked<unlocked<joinable` forces green. _(world-map.instructions.md; world_map.dart; [gated] [staging-only] [flaky])_
- [ ] Inspect a partially-completed unlocked activity (small/mid pin) — **Expect:** progress is an inner yellow dot whose radius grows with stars-earned fraction; it never recolors (stays purple) or hides the pin; fill renders only on unlocked pins. _(world-map.instructions.md; [staging-only])_
- [ ] Inspect an item that is finished AND has a live session — **Expect:** highest state on the ladder wins → displays joinable/green, despite being finished. _(world-map.instructions.md; world_map_ranking.dart)_
- [ ] Inspect a fully-completed activity with no live session — **Expect:** keeps unlocked (purple) color per fill-not-state (no separate gold pin); large card adds a "Completed" marker + Play again / Review; forced to smallest tier for auto-featuring but still expands on tap. _(world-map.instructions.md; [staging-only])_
- [ ] Brand-new joiner, zero stars: inspect first-Mission and later-Mission activities + cluster Stars — **Expect:** first-Mission unlocked (purple, empty fill); later-Mission locked (gray); cluster Stars = 0; nothing pre-unlocked beyond index 0. _(world-map.instructions.md; lo_progression.dart; [staging-only])_

### 2c. Feature the best content (desktop large cards)

- [ ] On a wide viewport with an open joinable session / in-course unlocked activity in view — **Expect:** only joinable open sessions and in-course unlocked activities earn auto-featured large cards (1–3 max, joinable first); locked/finished never auto-promoted to large. _(world-map.instructions.md; world_map_ranking.dart; [world-map-pins])_
- [ ] With >3 eligible items, watch large cards ~10–15s without interacting — **Expect:** large slots rotate through the eligible pool ~every 5s; with ≤3 eligible they stay static. _(world-map.instructions.md; world_map.dart; [world-map-pins] [flaky])_
- [ ] Pan/zoom to a new region and let it settle — **Expect:** featured cards re-rank/re-fill for the new viewport; a small pan does not reshuffle (tier assignment debounced/stable between nearby frames). Assert on the FINAL settled framing. _(world-map.instructions.md; [world-map-pins] [flaky])_

### 2d. Inspect / open a pin

- [ ] Tap a small/mid pin once — **Expect:** promotes to its large card in place over the map (no separate popup); on narrow, bottom nav still shows (it's a pin, not a sheet). _(world-map.instructions.md; routing.instructions.md)_
- [ ] Tap a large card for an unlocked activity — **Expect:** the plan page opens (left-column detail on desktop / bottom sheet on narrow); tapping empty map collapses a promoted card. _(world-map.instructions.md; routing.instructions.md)_
- [ ] Tap a locked pin → expand → open plan — **Expect:** locked large card is grayed with a lock over the thumbnail, empty star row, unlock-requirement line; plan opens read-only with Start gated. _(world-map.instructions.md; [gated] [staging-only])_
- [ ] Tap a completed activity → expand — **Expect:** card keeps unlocked (purple) color, adds Completed marker + Play again / Review; plan offers replay or review. _(world-map.instructions.md)_
- [ ] Zoom out until multiple pins overlap, then zoom in / tap the cluster bubble — **Expect:** overlapping pins collapse into a state-colored count bubble (Grouped) that de-overlaps and expands on zoom/tap. _(world-map.instructions.md)_

### 2e. Join the course

- [ ] Open a class link `/#/join_with_link?classcode=XYZ` logged in, not a member — **Expect:** navigates to `/join_with_link`, saves code to `SpaceCodeRepo`, redirects to `/home`; `joinCachedSpaceCode()` fires knock_with_code + join → user ends a joined member with no further interaction. _(joining-courses.instructions.md Route 1; [gated])_
- [ ] Open the join link while logged OUT, then complete account creation — **Expect:** the class code persists on disk across login; after creation `joinCachedSpaceCode()` auto-joins. Do NOT clear browser storage mid-journey. _(joining-courses.instructions.md Route 1; [gated] [flaky])_
- [ ] Open `/join?classcode=XYZ` (the alias route) — **Expect:** identical pageBuilder to `/join_with_link`; auto-joins the same way. _(routes.dart)_
- [ ] Enter-code page: type a valid code, submit — **Expect:** saves `recentCode`, POSTs knock_with_code, response `{roomIds, alreadyJoined, rateLimited}` drives `joinRoomById`; after sync navigates into the joined space. _(joining-courses.instructions.md Route 2; [gated])_
- [ ] Enter an invalid/nonexistent code — **Expect:** server-side validation fails, no invite/join; the join must not silently succeed. _(joining-courses.instructions.md Route 2; [gated])_
- [ ] Enter a code for a space already joined — **Expect:** `alreadyJoined=true` resolves to the existing membership (navigates there), no duplicate join. _(joining-courses.instructions.md Route 2; [gated])_
- [ ] Submit valid codes rapidly until `rateLimited=true` — **Expect:** client surfaces the rate-limited state, not a successful join. _(joining-courses.instructions.md Route 2; [gated] [flaky])_
- [ ] Open a knock-rule public room bottom sheet (from search) — **Expect:** a code field + "Ask to Join" button side by side (not a plain Join). Assert knock BEHAVIOR not exact label (labels differ across surfaces). _(joining-courses.instructions.md Route 3)_
- [ ] Open the public-room dialog / preview for a knock-rule room and tap Join — **Expect:** the button is a Knock; tapping issues `knockRoom()` (not a direct join) and shows a "You have knocked" confirmation; no membership change yet. _(joining-courses.instructions.md Route 3)_
- [ ] As space admin, open the member list with a pending knocker — **Expect:** knocking users sort below joined members, labeled "Knocking"; tapping shows an "Approve" action (visible only for `Membership.knock`) that calls `room.invite(userId)`; the knocker also appears in the space chat list. _(joining-courses.instructions.md Route 3; [gated])_
- [ ] As a previously-knocked user, receive the admin invite via sync — **Expect:** because the room is in the KnockTracker account-data record, the client auto-joins on invite arrival and clears the record — NO accept/decline dialog. Allow for sync latency. _(joining-courses.instructions.md; [gated] [staging-only] [flaky])_
- [ ] Receive an unsolicited space invite (not knocked, not a child of a joined parent, no code just entered) — **Expect:** none of the auto-join priority conditions match → accept/decline dialog shown. _(joining-courses.instructions.md; [gated])_
- [ ] As a joined member of a parent space, receive a child-space invite — **Expect:** auto-joins with NO prompt (priority #1). _(joining-courses.instructions.md; [gated])_
- [ ] Enter a valid code, then watch the incoming space invite during the same flow — **Expect:** the sync handler SKIPS the invite (recentCode dedup, priority #2), letting Route 2 own the join; no duplicate dialog. Set recentCode first or it races. _(joining-courses.instructions.md; [gated] [flaky])_
- [ ] Freshly join a course with default child chats — **Expect:** default chats (announcements, introductions, activity chats) auto-join on viewing the course; learner doesn't accept each room. _(joining-courses.instructions.md)_
- [ ] As a student, receive an analytics-room access invite — **Expect:** analytics-room invites always auto-join immediately (no prompt); instructor analytics access granted automatically. _(joining-courses.instructions.md; [gated] [staging-only])_
- [ ] Tap a course the user previously LEFT (still in their list) — **Expect:** auto-join via `room.join()` without explicit confirmation. _(joining-courses.instructions.md; [gated])_
- [ ] Open a class link in a MOBILE web browser, app not installed, hash has `join_with_link` — **Expect:** the `web/index.html` `pangea://` redirect is SKIPPED (custom scheme would lose the fragment); the Flutter web app loads and processes the code directly. _(joining-courses.instructions.md; [flaky] [staging-only])_
- [ ] Open the class link where no native app intercepts — **Expect:** web app processes the code directly, no deferred-deep-link service; join completes in the browser. _(joining-courses.instructions.md)_
- [ ] Navigate to `/courses/preview/:courseroomid` for a public/knock room, not a member — **Expect:** `PublicCoursePreview` loads (loadCourse → loadTopics), shows course detail with a Join/Knock affordance — browsable before joining. _(routes.dart; course-plans.instructions.md)_

### 2f. Course scope, panels & navigation

- [ ] Open a course from a map pin / course tile, inspect URL + map — **Expect:** sets `?m=course:<id>` (map scoped to that course's activities) AND opens `left=course`; the panel reads its space id from `?m=`, not duplicated into the token. _(routing.instructions.md)_
- [ ] Close the course card (X) on a course-scoped map — **Expect:** drops only the course token; `?m=course` persists (map stays scoped, card gone). Scope resets only via the World control. _(routing.instructions.md)_
- [ ] Click World / home in the nav rail inside a scoped course with panels open — **Expect:** every panel closes AND the map returns to world scope (`?m=` cleared) in ONE history step — back restores both panels and scope together. _(routing.instructions.md)_
- [ ] Wide viewport, left panel + right companion open: select a different section (Chats/Courses) in the rail — **Expect:** the rail selection REPLACES open left-column panels with that section; right-column companions stay open. _(routing.instructions.md)_
- [ ] Wide viewport, live chat open on left: open a course from a pin/tile (not a rail button) — **Expect:** keeps the open chat and swaps only the course (content nav, not a section switch). _(routing.instructions.md)_
- [ ] Click the Courses icon in the nav rail (≥1 joined course) — **Expect:** a left-column master with a flat list of joined-course tiles (image, name, participants, level, modules) + add-course options (start-my-own / browse / enter-code) below; URL carries the left token over `/`, not a `/courses` path. _(routing.instructions.md; routes.dart)_
- [ ] As admin, open Invite-by-Email from the course card More menu, enter emails, submit — **Expect:** calls the Synapse invite_by_email endpoint with `{room_id, emails, message?}` using the teacher's token; toast confirmation (fire-and-forget); response `{emailed, errors}`. _(invite-by-email.instructions.md; [gated] [staging-only])_
- [ ] As a non-admin (power < 100), attempt Invite-by-Email — **Expect:** the action is gated to admins (power 100); a non-admin cannot successfully invite. _(invite-by-email.instructions.md; [gated])_
- [ ] As admin on a wide layout, open a course management page (invite/edit/access) from the card — **Expect:** opens as a coexisting detail BESIDE the card (a `coursepage` token; card is master), not replacing it; closing reveals the card. Under width pressure it folds to a push (back arrow reopens card). _(routing.instructions.md; [recently-changed])_
- [ ] Open a course management page on a narrow screen — **Expect:** single-column shows one panel: management page is a push over the card with a back arrow that reopens the card (master one step away, never discarded). _(routing.instructions.md; [recently-changed])_
- [ ] Navigate directly to a legacy course path `/courses/!spaceid` — **Expect:** redirected to `/?m=course:!spaceid&left=course` at the router redirect before render; the map never double-rebuilds (a visible world↔course flicker is itself a failure). `/courses/!spaceid/!roomid` adds the room as a left token beside the course. _(legacy_redirects.dart; routing.instructions.md; [recently-changed])_

### 2g. Run an activity (start → live → review)

- [ ] Open an activity from inside a course (`?m=course:<id>` survives) — **Expect:** opens as a side panel (desktop) / bottom sheet (narrow) over the persistent map (not remounted); camera biases to the pin; the plan is the card's CHILD and closes with a back-arrow that reopens the course card. _(routing.instructions.md; activities.instructions.md)_
- [ ] Open `/<activityId>` (UUID) standalone with no course selected, then close — **Expect:** the same panel opens; client resolves the parent course (first joined course whose plan includes the activity) or none (course-less session valid); closing returns to World `/` with an X (not a back-arrow). _(activity_detail_panel.dart; activities.instructions.md)_
- [ ] Open `/<activityId>?launch=true` — **Expect:** begins launching a session immediately, skipping the not-started start screen. _(activity_detail_panel.dart; activities.instructions.md; [gated])_
- [ ] Open `/<activityId>?roomid=<sessionRoomId>` with an in-progress session — **Expect:** re-enters that specific session room rather than starting fresh. _(activity_detail_panel.dart; activities.instructions.md; [staging-only])_
- [ ] Navigate directly to a LOCKED course activity's `/<activityId>?launch=true` — **Expect:** the lock holds — `startNewActivity` early-returns when `_isLocked`; the deep link cannot bypass the gate. (Standalone-with-no-course fails open; the guard bites only when a launching course context resolves it locked.) _(not_started_session_controller.dart; [gated] [staging-only])_
- [ ] Cold-open a standalone `/<UUID>` activity with NO course context — **Expect:** treated as UNLOCKED (fail open): Start enabled, not the disabled "Finish the previous mission" state. `_resolveLock` returns early when course/uuid null. _(quests.instructions.md; not_started_session_controller.dart)_
- [ ] View an activity's not-started start page (no session room yet) — **Expect:** reflects room facts (no room); shows waiting-room affordances: ping the course, play with the bot, invite a friend. State read from the room, not stored locally. _(activities.instructions.md)_
- [ ] Tap "ping the course" twice within one minute — **Expect:** rate-limited to once/minute; the second ping is blocked/disabled. _(activities.instructions.md; [gated])_
- [ ] Open the role picker, take a role; fill all roles — **Expect:** picker shows in "picking a role"; after taking a role → "in with a role"; when all roles filled → "session full". Each step derived from room facts. _(activities.instructions.md)_
- [ ] Enter a started activity session — **Expect:** runs as an ordinary Matrix chat room (timeline, sync, membership, roles), a live left-column chat, NOT an immersive takeover; the room IS the session. _(activities.instructions.md; routing.instructions.md)_
- [ ] Live activity chat open on left + open an analytics/construct detail on the right — **Expect:** role decides side: the live chat stays open on the left while the right-column panel shows; a live `room` is independent of the shared detail slot. _(routing.instructions.md)_
- [ ] With one live view open (chat OR session review), open a second live view — **Expect:** at most ONE live view: opening another `room`/`session` drops the first (shared Matrix timeline, not reference-counted). Test sequentially. _(routing.instructions.md; [flaky])_
- [ ] Open a completed activity session (Stars tracker → sessions panel, or its entry) — **Expect:** opens as the activity's ACTUAL chat (real timeline), locked from new messages, wrap-up summary posted IN the timeline as a message (not a separate summary card); rendered via a `session` token. _(routing.instructions.md)_
- [ ] Reach the "ended" state, then revisit the start page — **Expect:** the client fires the summary once the session ends and keeps a short-lived local analytics cache so the page does NOT re-fetch on every visit. (Activity-ended is the org doc's call; wait for the transition.) _(activities.instructions.md; [flaky])_

### 2h. Activity media

- [ ] Observe an activity card / map pin BEFORE opening it — **Expect:** thin fields only (title, level, place, searchable basics) + at most ONE thumbnail; full plan/media not loaded. A missing thumbnail on an unopened card is not a bug. _(activities.instructions.md; [gated])_
- [ ] Locate the single media block on a video-first card/pin — **Expect:** the first block stands in for the carousel and carries a play badge (it's a video); no carousel paging on the compact surface. _(activities.instructions.md; [gated])_
- [ ] Tap the play-badged block on a card/pin — **Expect:** does NOT play in place; opens the activity with that video starting (muted, tap-to-unmute) — the only self-start; autoplay rides with the activity link. (Unmuted autoplay is correctly blocked by browsers.) _(activities.instructions.md; [flaky])_
- [ ] Swipe a multi-block (image+audio+video) stimulus on a focused surface — **Expect:** the whole carousel in set order; nothing autoplays; a video plays only on tap; each block plays in place (images show, uploaded video uses the app player, YouTube embeds). _(activities.instructions.md)_
- [ ] View a single-media activity stimulus on a focused surface — **Expect:** the carousel degrades to a single display with NO paging/navigation controls. _(activities.instructions.md)_
- [ ] Open an activity whose uploaded (non-YouTube) media fails to resolve to a URL — **Expect:** unresolved uploaded media falls back to a placeholder; a YouTube block is exempt (carries its own link). On web a placeholder may indicate a CDN CORS gap, not a missing asset. _(activities.instructions.md; [flaky])_
- [ ] Tap a YouTube block on a focused surface — **Expect:** plays as an embed (never downloaded/re-hosted), only on tap. _(activities.instructions.md)_

### 2i. Stars roll up & next Mission unlocks

- [ ] Earn stars in the first Mission up to the threshold (default 10 or course override), return to the course map / next activity's plan without a hard reload — **Expect:** the next Mission's pin flips gray→purple and its Start enables; the gate rebuilds per-frame from outlines+stars and the awarded-goal room-state stream re-triggers it. Stars summed across the prior Mission, best-per-activity (a replay doesn't multiply). Allow for sync/debounce settle; don't hard-reload mid-assertion. _(quests.instructions.md; lo_progression.dart; world_map.dart; [gated] [staging-only] [flaky])_
- [ ] In a course whose teacher overrode `starsToUnlockObjective`, earn stars to that overridden count — **Expect:** unlock happens at the COURSE's threshold, not the default 10. Read the course's threshold, don't hardcode 10. _(lo_progression.dart; not_started_session_controller.dart; [gated] [staging-only])_
- [ ] Compare the cluster Stars count to the sum of per-pin star fills (with ≥1 replayed activity) — **Expect:** cluster Stars = stars summed across activities, best-per-activity (a replay doesn't multiply), from awarded-goal room state (same source as the quest LO gate), agreeing with the per-pin fill — NOT the analytics streams. _(routing.instructions.md; user_stars.dart; [staging-only])_
- [ ] Two joined courses share an LO; A leaves it gated, B has unlocked it — view an activity carrying that shared LO — **Expect:** reads UNLOCKED — an objective unlocked by ANY joined course wins (`buildLoGate` unions unlocked sets across outlines). _(lo_progression.dart; [gated] [staging-only])_
- [ ] View a later-Mission activity pin NOT joined, then join the course and view again — **Expect:** before joining its sequence isn't a gate input (not gated); after joining the same activity reads locked (gray) until its prerequisite is met. Leaving removes the gating again. _(quests.instructions.md; world-map.instructions.md; [gated] [staging-only])_
- [ ] Refresh a course-scoped URL showing a locked activity's plan (`?m=course:<id>` + activity open) — **Expect:** refresh restores the same panels/scope (URL is the single source of truth); the activity re-resolves its course via surviving `?m=course` and re-gates. (Caveat: a bare `/<UUID>` with no scope fails OPEN on cold load — renders unlocked, intended.) _(routing.instructions.md; quests.instructions.md; activity_detail_panel.dart)_

---

## Journey 3 — Subscription & Paywall

Money path — test first. The trial-window inversion is the key trap: a fresh account (<7 days) silently unlocks everything, so paywall/lock tests need an account >7 days old with no active subscription.

- [ ] Free user (account >7 days, no subscription), tap a reading-assistance tool in the message toolbar — **Expect:** an `ErrorIndicator` "subscribe to unlock reading assistance" replaces the tool and calls `SubscriptionPaywall.show`; the real tool must NOT render. _(subscriptions.instructions.md; [gated])_
- [ ] Free user (not in trial), trigger the paywall (with products cached, not in backoff) — **Expect:** a modal bottom sheet titled "Get Access" with one `SubscriptionCard` per visible web subscription (displayName, displayPrice, Subscribe); closing records a dismissal. _(subscriptions.instructions.md; [gated])_
- [ ] New user inside the trial window (<7 days), trigger any paywall entry point — **Expect:** the paywall does NOT open and gated content IS shown (`showSubscriptionGatedContent==true` while `inTrialWindow`); the Pro feature works during the trial. _(subscriptions.instructions.md; [gated])_
- [ ] Trial-window user, open the paywall (forced) and tap the trial card — **Expect:** exactly ONE card (the trial card), not paid plans; tapping calls `activateNewUserTrial` → `activateFreeTrial`, refreshes to active-promotional. _(subscriptions.instructions.md; [gated])_
- [ ] Open Settings → Subscription Management (cluster avatar → settings) — **Expect:** opens as `settingspage:subscription` detail (`right=settingspage:subscription`) showing the Pro Features card + star background + management/plan-picker; URL token, not a full route nav. _(subscriptions.instructions.md)_
- [ ] Unsubscribed web user, expand a plan and tap Pay — **Expect:** `submitSubscriptionChange` → Stripe PaymentLink with the plan's duration, sets `beganWebPayment`, navigates the SAME tab to Stripe checkout (`_self`); duration matches the tapped plan. _(subscriptions.instructions.md; [staging-only] [gated])_
- [ ] Read the plan-picker price + breakdown — **Expect:** web price renders `$<price>` from RC Offering metadata (localizedPrice null on web), shown `<price>/<duration>`. May legitimately differ from the Stripe checkout price (documented gap), not necessarily a failure. _(subscriptions.instructions.md)_
- [ ] Scroll to the bottom of the plan picker (web) — **Expect:** a web-only info row (info icon + "promo code" message) telling the user discount codes are entered at Stripe checkout; absent on mobile. _(subscriptions.instructions.md)_
- [ ] Return from Stripe checkout with `beganWebPayment` set and `/subscription` now active — **Expect:** `_handleWebSubscriptionFlow` clears the flag and fires `_onSubscribe` → "Successfully subscribed" snackbar with a "click to manage" link; gated Pro content becomes available. _(subscriptions.instructions.md; [staging-only] [flaky])_
- [ ] Active web (Stripe) subscriber opens the subscription page — **Expect:** management options render (Current Subscription, Cancel subscription, Payment method, Payment history, "renews on <date>"); the plan picker is hidden. _(subscriptions.instructions.md; [staging-only] [gated])_
- [ ] Tap "Cancel subscription" (active web sub) — **Expect:** Stripe billing portal opens externally at `STRIPE_MANAGEMENT_LINK?prefilled_email=<encoded>`; a 30s snackbar with "Try again" re-launches it; `clickedCancelSubscription` timestamp recorded. _(subscriptions.instructions.md; [staging-only])_
- [ ] Re-open the subscription page <10 min after clicking cancel — **Expect:** a "waiting for changes" italic info row shows below the date while the cancel is pending and the 10-min window hasn't elapsed; clears after the end date changes or 10 min pass. _(subscriptions.instructions.md; [staging-only] [flaky])_
- [ ] Active sub with `unsubscribeDetectedAt` + expirationDate set — **Expect:** the date row reads "Subscription ends on <date>" (not "renews on") and the cancel row becomes an "Enabled renewal" / refresh action. _(subscriptions.instructions.md; [staging-only])_
- [ ] Subscriber who bought on another platform (appId ≠ stripeId/currentAppId) opens the page on web — **Expect:** `ManagementNotAvailableWarning` ("Originally subscribed on <platform>") instead of cancel/payment rows; cannot cancel from web. _(subscriptions.instructions.md; [staging-only] [gated])_
- [ ] Promotional (`rc_promo` prefix) / lifetime (expiry >2100) subscriber opens the page — **Expect:** promo/lifetime copy via `ManagementNotAvailableWarning` (lifetime → promotionalSubscriptionDesc; promo → trialExpiration(date)); `hasPaidSubscription` false. _(subscriptions.instructions.md; [staging-only] [gated])_
- [ ] Free user (not in trial), tap Practice on the vocab/grammar analytics panel — **Expect:** `UnsubscribedPracticePage` (shimmer, lock icon, decorative stars) with an "Unlock practice activities" button calling `SubscriptionPaywall.show`; no real exercise content reachable. _(subscriptions.instructions.md; practice-exercises.instructions.md; [gated])_
- [ ] Free user (not in trial), open a completed activity's wrap-up summary — **Expect:** an `ErrorIndicator` "subscribe to unlock activity summaries" replaces the summary; tapping opens the paywall. _(subscriptions.instructions.md; [gated])_
- [ ] Free user (not in trial), request phonetic transcription (backend raises `UnsubscribedException`) — **Expect:** `ErrorIndicator` "subscribe to unlock transcriptions"; a non-subscription error shows a generic indicator instead. _(subscriptions.instructions.md; [gated])_
- [ ] Free user (not in trial), tap a token whose word card is gated — **Expect:** `MessageUnsubscribedCard` (shimmer + word in yellow) with an "Unlock learning tools" pressable calling `SubscriptionPaywall.show`. _(subscriptions.instructions.md; [gated])_
- [ ] Previously-dismissed paywall within the backoff window: tap a token that would auto-show the inline `PaywallCard` (`force:false`) — **Expect:** the inline card does NOT appear (`shouldShowPaywall` false; backoff = 1h × dismissal count); reappears only after the window elapses. _(subscriptions.instructions.md; [gated] [flaky])_
- [ ] Dismiss the paywall bottom sheet (backoff 0), then re-trigger within the hour — **Expect:** first dismissal increments backoff to 1; the auto inline card is suppressed ~1h. A forced entry (gated `ErrorIndicator`) can still open it (`SubscriptionPaywall.show` ignores backoff; only early-returns on empty products / gated-content-shown). Don't conflate the two show paths. _(subscriptions.instructions.md; [gated] [flaky])_
- [ ] View the top of the subscription page (any state) — **Expect:** a gold-framed "Pro Features" card lists six benefits (pronunciation tools, audio transcription, visual learner support, instant writing translation, personalized practice, vocabulary flashcards). _(subscriptions.instructions.md)_
- [ ] Trigger the paywall when `availableSubscriptions` resolves empty (cold cache + products unavailable) — **Expect:** the bottom sheet does NOT open (early-return on empty); the gated CTA remains but tapping produces no modal. Pricing can be stale across relaunches (GetStorage-first cache). _(subscriptions.instructions.md; [gated] [flaky])_
- [ ] Navigate directly to the legacy `/rooms/settings/subscription` (or `/settings/subscription`) — **Expect:** redirected to `right=settingspage:subscription` before render; the management page shows; the persistent map/shell is not torn down. _(routing.instructions.md; [recently-changed])_

---

## Journey 4 — In-chat reading & writing assistance

Toolbar overlays + word cards over the live chat; writing-assistance ring and span cards in the input. All token-driven overlays over path `/` — assert via UI/tokens, never path navigation.

### 4a. Reading toolbar & word card

- [ ] Tap a received L2 text message bubble (tokens available) — **Expect:** an overlay composited over the chat (no route push, URL stays `/`), each word tappable, action buttons (audio, translate, practice, emoji) below; dismissing returns to the exact same chat state. _(toolbar-reading-assistance.instructions.md; [gated])_
- [ ] Open the toolbar on an L2 message, an L1 message, and an unknown-language message — **Expect:** L2 → all modes; L1 → no modes (nothing to learn); unknown → only translate. _(toolbar-reading-assistance.instructions.md; [gated])_
- [ ] Open the toolbar on a received voice/audio message not in L1 — **Expect:** speech-transcription + translation modes (STT transcript + translation) instead of text modes; tapping a transcript word plays it / shows meaning. _(toolbar-reading-assistance.instructions.md)_
- [ ] Tap a message before tokens resolve — **Expect:** the toolbar shows limited functionality rather than failing; word-level features unavailable until tokens load. (Wait for token rendering before asserting modes.) _(toolbar-reading-assistance.instructions.md; [flaky])_
- [ ] Tap an individual word token (select mode) — **Expect:** a word card above the message: lemma, meaning, phonetic transcription, emoji (or picker), feedback flag; TTS speaks the word (unless already in audio mode). _(toolbar-reading-assistance.instructions.md)_
- [ ] Tap a green-underlined (never-tapped) word — **Expect:** the green underline disappears globally for that word, a small click-XP bonus is awarded, the word is tracked as a vocabulary-garden seed. _(toolbar-reading-assistance.instructions.md)_
- [ ] Tap the same word again (same session) — **Expect:** no additional XP — only the first interaction per word per session counts (first-click-only analytics). _(toolbar-reading-assistance.instructions.md)_
- [ ] Open the toolbar, do nothing, then tap Translate, then Audio (watch network) — **Expect:** nothing prefetched on message tap; the translation request fires only on Translate, the TTS request only on Audio (lazy loading). _(toolbar-reading-assistance.instructions.md)_
- [ ] Tap Translate on an L2/unknown message — **Expect:** a full L1 translation appears below the message (one step removed, not auto-shown). _(toolbar-reading-assistance.instructions.md)_
- [ ] Tap Audio, let the sentence play, then tap one word — **Expect:** full-sentence TTS with each word highlighting in sync with TTS timing; tapping a word plays it in isolation. (Highlight-sync is timing-sensitive; assert presence over exact frame.) _(toolbar-reading-assistance.instructions.md; [flaky])_
- [ ] With a word card showing, change available width (open a panel / resize) — **Expect:** the overlay dismisses rather than repositioning; it does not re-anchor to the bubble. _(toolbar-reading-assistance.instructions.md; [flaky])_
- [ ] Tap Practice on an L2 text message — **Expect:** the message animates to center and enlarges; practice buttons appear on each eligible word (listening, meaning, emoji, grammar); completed modes turn gold. _(toolbar-reading-assistance.instructions.md)_
- [ ] Tap Emoji, pick an emoji for a word, then re-encounter that word — **Expect:** an emoji picker per word; the chosen emoji appears on that token in future encounters; associations persist via the Matrix analytics room and sync across devices. _(toolbar-reading-assistance.instructions.md)_
- [ ] Tap the flag on a word card, describe a problem, submit — **Expect:** a free-text dialog opens; on submit the server re-evaluates, returns updated fields, and the UI replaces the old word-card content; the flag is recorded server-side with the user's identity. _(toolbar-reading-assistance.instructions.md; token-info-feedback-v2.instructions.md; [recently-changed] [staging-only])_
- [ ] Submit token feedback about meaning (not phonetics) with stale local phonetics — **Expect:** `updatedPhonetics` may still be non-null — the server returns the current CMS version; the client applies it to the v2 PT cache and the transcription refreshes. _(token-info-feedback-v2.instructions.md; [recently-changed] [staging-only] [flaky])_
- [ ] Translate mode with a wrong full-text translation: look for a flag beside the translation — **Expect:** PLANNED — a flag (same icon/dialog/UX as word-card feedback) regenerates with a stronger model + feedback as context. Absence may be correct on current builds; treat as a known-state check. _(toolbar-reading-assistance.instructions.md; [recently-changed] [flaky])_

### 4b. Phonetic transcription

- [ ] Read the transcription line on a word card (any L1/L2, incl. Latin-script) — **Expect:** a pronunciation tailored to the user's L1 (e.g. "lluvia" → "YOO-vee-ah" for English L1); computed from lang_code + user_l1 (user_l2 doesn't affect it). _(phonetic-transcription-v2-design.instructions.md; [staging-only])_
- [ ] Open a word card for a heteronym whose POS/morph context uniquely matches one `ud_conditions` entry — **Expect:** exactly ONE transcription displayed (the matching one); not all pronunciations shown. _(phonetic-transcription-v2-design.instructions.md; [staging-only])_
- [ ] Open a word card for a heteronym whose context does NOT narrow to one match — **Expect:** all pronunciations displayed (e.g. "hái / huán"), each with its own play button speaking its specific tts_phoneme. _(phonetic-transcription-v2-design.instructions.md; [staging-only])_
- [ ] Open a vocab construct detail (cluster → vocab tracker → tap a construct) — **Expect:** pronunciation is the lemma's dictionary pronunciation (surface=lemma, lang_code=userL2Code; ud_conditions matched against lemma+POS, case-insensitive); NO per-inflected-form audio buttons (form pronunciation lives in chat). _(phonetic-transcription-v2-design.instructions.md; [recently-changed] [staging-only])_

### 4c. Word-level TTS

- [ ] Free user taps a word audio button — **Expect:** device TTS plays (best local voice); it does NOT error or hit the backend (backend TTS is entitlement-gated, 401 for free users — subscription is the first routing branch). _(word-text-to-speech.instructions.md; [gated])_
- [ ] Subscribed user, L2 word with no known-good device voice — **Expect:** a `POST /choreo/text_to_speech` fires and high-quality backend audio plays (check-first, backend-second); when a good device voice IS available it plays locally with no backend call. _(word-text-to-speech.instructions.md; [gated] [staging-only])_
- [ ] Subscribed user taps the same word twice (already backend-fetched) — **Expect:** no new backend request — served from the client-side short-TTL cache; repeated taps don't re-hit or re-bill (holds within the TTL + one session). _(word-text-to-speech.instructions.md; [gated])_
- [ ] Subscribed user plays an L2 heteronym whose PT v2 cache holds a resolved `tts_phoneme` — **Expect:** routes to backend (only backend renders phonemes), using the single resolved phoneme from the local PT cache (no blocking call); a cache miss falls through to normal routing. (Trigger the transcription render first to seed the cache.) _(word-text-to-speech.instructions.md; phonetic-transcription-v2-design.instructions.md; [gated] [staging-only])_

### 4d. Writing assistance (ring + span card)

- [ ] Observe the assistance ring with an empty input — **Expect:** grey check + 5 grey segments (idle); the ring is a status indicator only — tapping it does NOT navigate between matches. _(writing-assistance.instructions.md; [recently-changed])_
- [ ] Type L2 text with an issue, wait for the debounced `/grammar_v2` fetch — **Expect:** while fetching, segments spin and the check is hidden; on matches the outer edge divides into one segment per match, each colored by `ReplacementTypeEnum`, bright (full opacity) for unviewed. _(writing-assistance.instructions.md; [recently-changed] [staging-only] [flaky])_
- [ ] Type clean, correct L2 text, wait for the response — **Expect:** check icon visible with a solid green ring (zero matches). _(writing-assistance.instructions.md; [recently-changed] [staging-only])_
- [ ] Clear the input while segments are showing — **Expect:** the ring animates out and returns to idle (grey check, 5 grey segments). _(writing-assistance.instructions.md; [recently-changed] [flaky])_
- [ ] Type text with a surface error (punctuation/diacritics/spelling/capitalization), wait — **Expect:** surface matches auto-applied (text replaced) and highlighted bright mint-green immediately; an `AutocorrectPopup` toast briefly shows so the edit isn't silently swallowed; status `automatic`. _(writing-assistance.instructions.md; [recently-changed] [staging-only] [flaky])_
- [ ] Tap a highlighted (unviewed) match in the input — **Expect:** the span card anchors to it: close (✕), edit-category header (e.g. "Verb Conjugation"), flag (🚩), left-aligned bot face + hint, a row of choices (horizontal if they fit, else vertical, undo at the end). _(writing-assistance.instructions.md; [recently-changed] [staging-only])_
- [ ] With the span card open on an unviewed match, navigate away (tap elsewhere / close / outside) — **Expect:** the match is marked viewed; its highlight + ring segment go bright (open→viewed; segments muted while open, bright once viewed); the card stays as a single reusable popup. _(writing-assistance.instructions.md; [recently-changed] [staging-only])_
- [ ] With ≥2 matches and the card open on one, tap a different match — **Expect:** the SAME persistent card updates content (no per-match overlay create/destroy) and animates (slide + crossfade) to the new position, not teleporting. _(writing-assistance.instructions.md; [recently-changed] [flaky])_
- [ ] Tap the best-replacement choice — **Expect:** text replaced, match accepted (highlight stays bright), card advances to the next unviewed match (or closes if none remain). _(writing-assistance.instructions.md; [recently-changed] [staging-only])_
- [ ] Tap a non-best choice (alt, then distractor) — **Expect:** the choice changes color as feedback (alt = lighter green, distractor = red) rather than applying immediately; tapping again applies it. No Ignore/Replace buttons or bottom button row. _(writing-assistance.instructions.md; [recently-changed] [staging-only])_
- [ ] Tap an already-accepted / auto-applied bright highlight — **Expect:** the card reopens with a compact `original → replacement` diff + undo (↩) instead of the choices row; undo reverts and restores the full choices view (match → viewed). Same for auto-applied. _(writing-assistance.instructions.md; [recently-changed] [staging-only])_
- [ ] Tap Send while matches are unviewed — **Expect:** the message sends regardless of match status (no gate); on send the choreographer tokenizes the final text (`/choreo/tokenize`) and saves a `ChoreoRecordModel` recording which matches were viewed/accepted/open. _(writing-assistance.instructions.md; [recently-changed] [staging-only])_
- [ ] Edit text in a matched region after matches are present, wait — **Expect:** the icon spins again, old segments cleared/discarded, and the new `/grammar_v2` response rebuilds the ring from scratch. (Assert post-fetch state, not mid-fetch.) _(writing-assistance.instructions.md; [recently-changed] [staging-only] [flaky])_
- [ ] Tap the flag (🚩) on a span card, enter feedback + thumbs up/down, submit — **Expect:** feedback submitted (thumbs maps to score 10/0); server audits, escalates the model if rejected, persists the judgment. _(writing-assistance.instructions.md; [recently-changed] [staging-only])_
- [ ] Engage writing assistance and look for legacy IT UI — **Expect:** NONE of the deprecated Interactive Translation / accept-reject UI appears — no IT bar, no Ignore/Replace buttons, no autorenew spinner, no elevation/shadow state changes. Translation is delivered as a match type. _(writing-assistance.instructions.md; [recently-changed])_

---

## Journey 5 — Profile & Settings

Save → Matrix account data → sync round-trip → stream dispatch; the public/private boundary; bot-option propagation; inline language-switch prompts.

- [ ] Open Learning settings (cluster avatar → Settings → Learning, or the flag shortcut), change a non-language setting (CEFR/gender/voice), save — **Expect:** writes Matrix account data via `UserController.updateProfile`, waits for the sync round-trip, dispatches on `settingsUpdateStream` (NOT `languageStream`); persists after refresh. (Assertions immediately after Save can race the round-trip — poll until settled.) _(profile.instructions.md; [staging-only])_
- [ ] Change target OR source language and save — **Expect:** fires `languageStream` (heavyweight): cache clearing, bot-option propagation, public-profile sync; analytics context reinitializes per the new L2 (per-language isolation); the cluster flag updates. _(profile.instructions.md; analytics-system.instructions.md; [gated] [staging-only])_
- [ ] Edit country (and/or about), save, observe what a second account sees on this profile — **Expect:** only country and about sync to `PublicProfileModel`; CEFR, gender, voice, tool toggles stay private; other users see DERIVED analytics levels, not the self-reported CEFR. _(profile.instructions.md; [staging-only])_
- [ ] Open the bot's member profile in a clean 1:1 DM, change a bot option, save — **Expect:** the DM's `pangea.bot_options` room state updates eagerly/immediately (path 5 calls propagation directly, not waiting for the sync stream). _(profile.instructions.md; [gated] [staging-only])_
- [ ] In an activity room (has `pangea.activity_plan` state) + a clean bot DM, change a learning setting and let propagation run — **Expect:** the bot DM gets updated options but the activity room does NOT (excluded by the `pangea.activity_plan` presence filter; activity rooms manage their own options). Verify against the bot DM, not a stale activity room. _(profile.instructions.md; [gated] [staging-only])_
- [ ] In an activity room whose target language ≠ current L2 (no prompt in last 30 min), type a message and send — **Expect:** a popup offers to switch L2; on confirm it updates `targetLanguage` and auto-sends the pending message; a second send within 30 min in the SAME room does NOT re-prompt (rate-limited per room). Use a fresh room to re-test. _(profile.instructions.md; [flaky] [gated] [staging-only])_
- [ ] Tap a message in a language ≠ L2 where the selected reading mode is unavailable — **Expect:** a snackbar with a "Learn" button that switches `targetLanguage` (path 7 — only changes targetLanguage, bypasses full settings UI). _(profile.instructions.md; [gated] [staging-only])_
- [ ] Pick a target language (L2) vs native (L1) in learning settings — **Expect:** L2 options show only languages with L2 support (`l2Support != na`); L1 options show all (no filter); regional variants render with a locale emoji ("Portuguese 🇧🇷", not "Portuguese (Brazil)"). _(language-list.instructions.md)_
- [ ] Inspect the course-creation language picker — **Expect:** uses `unlocalizedTargetOptions`: L2-supported languages EXCLUDING regional variants (keeps "Portuguese", not "Portuguese (Brazil)") — unlike the learning-settings picker which includes variants. _(language-list.instructions.md)_
- [ ] Open the cluster flag for an L2 with a single regional flag vs a region-ambiguous L2 — **Expect:** shows the flag image when a single regional flag exists (es-ES → flag); shows the uppercased language code when none (bare es → "ES"). _(routing.instructions.md; language-list.instructions.md)_
- [ ] Visit legacy deep links `/settings`, `/profile`, `/profile/edit`, `/analytics` directly — **Expect:** each rewritten to its canonical token (`/settings`→`right=settings`, `/profile/edit`→`right=settingspage:profile/edit`, `/analytics`→`right=analytics:<tab>`) before render; the path collapses to `/`. _(routes.dart; routing.instructions.md; [recently-changed] [staging-only])_
- [ ] Wide desktop: open settings master, open a settings page beside it, narrow below the breakpoint and widen back — **Expect:** under pressure the master FOLDS behind its detail (one back-step away, both stay in URL); widening UNFOLDS to two panels; the detail never replaces its master; closing the detail reveals the menu. _(routing.instructions.md; [staging-only])_
- [ ] Narrow viewport, live chat open: open settings/analytics over it (recency), then copy the URL and open it cold/refresh — **Expect:** in-session the most-recently-opened panel shows over the chat (recency wins); on a cold link/refresh (no recency) the shown panel falls back to the active leaf of the tree. Distinguish a live-recency test from a refresh test — different oracles. _(routing.instructions.md; [analytics] [flaky] [staging-only])_

---

## Journey 6 — Analytics

Cluster live counts, the Stars-vs-streams source distinction, master/detail with a single shared detail slot, vocab/grammar tabs, practice takeover.

- [ ] First map load with prior non-zero XP, then interact with a new word in chat — **Expect:** the cluster shows the XP ring, Stars/Grammar/Vocabulary trackers, level medal, L2 flag, populated from the analytics streams read inside a `StreamBuilder` subscribed during build (no stale/zero on first paint); a live word interaction updates the counts. (Allow the first live update before asserting — "zero on first load" can be a real bug OR a too-early read.) _(routing.instructions.md; analytics-system.instructions.md; [flaky] [staging-only])_
- [ ] Compare the cluster Stars count to the sum of per-pin fills (with a replayed activity) — **Expect:** Stars = best-per-activity summed across activities (replay doesn't multiply), from awarded-goal room state (NOT the analytics streams), agreeing with the per-pin fill; rebuilds on the goal room-state stream. _(routing.instructions.md; [gated] [staging-only])_
- [ ] Open the chat list and read the level/XP indicator vs the public profile level (local XP advanced since last public sync) — **Expect:** displayed level/XP comes from local `derivedData` (cachedDerivedData fallback), NOT the public-profile `AnalyticsProfileModel.level`; reflects the live local total even when the public profile lags. _(analytics-system.instructions.md; [staging-only])_
- [ ] Tap a cluster tracker (e.g. Vocabulary) — **Expect:** analytics opens as a RIGHT-column master (`right=analytics:vocab`); any open left-column live chat stays open (panels independent); the detail blooms to the LEFT of the master. _(routing.instructions.md; [staging-only])_
- [ ] With a live room chat open, tap a vocab item, then a grammar item, then a completed-activity session — **Expect:** vocab detail, grammar detail, and session review SHARE ONE detail slot across both columns — opening one closes the other two; the independent left-column live chat stays open. _(routing.instructions.md; [staging-only])_
- [ ] Tap the Stars tracker in the cluster — **Expect:** opens the sessions analytics panel (right column). _(routing.instructions.md; [staging-only])_
- [ ] Tap the level medal overhanging the powerups pill — **Expect:** opens the Level analytics tab as a right-column panel. _(routing.instructions.md; [staging-only])_
- [ ] Open the Grammar tab and expand a feature box (e.g. Tense) — **Expect:** only `display:true` (feature,value) pairs for the target_language appear, ordered by `sequence_position`; produced tags color-coded by proficiency, unencountered tags visible but DIMMED (intentional, not hidden). _(grammar-analytics.instructions.md; [gated] [staging-only])_
- [ ] Open a grammar tag detail with user_l1 set to a language with grammar-construct-meanings rows (e.g. ko) — **Expect:** feature title + per-value title/description render in the user's L1 from `POST /choreo/grammar_constructs` (not hardcoded client copy); a low-score L1 translation falls back to source_l1 text. _(grammar-analytics.instructions.md; [gated] [recently-changed] [staging-only])_
- [ ] Open the Grammar tab unauthenticated / offline — **Expect:** the client falls back to `defaultMorphMapping` — a usable inventory still renders, not a failure. _(grammar-analytics.instructions.md; [flaky])_
- [ ] Brand-new L2 (no morph construct ≥ Green / 50 XP): inspect Grammar vs Vocabulary — **Expect:** grammar constructs "unlock" only at Green (50 XP); sub-threshold constructs not yet surfaced as unlocked (discovery moment). Fresh accounts show empty/dimmed states that are correct, not failures. _(analytics-system.instructions.md; [gated] [staging-only])_
- [ ] Tap Practice on the vocab/grammar analytics panel (Pro, with a live left chat) — **Expect:** practice (`right=practice:<type>`) opens as a bounded right-column panel that TAKES OVER the analytics surface (master + any detail close, can't coexist while active); the left-column live chat stays open. _(routing.instructions.md; [staging-only])_
- [ ] Tap a brand-new word in the reading toolbar — **Expect:** a floating "+N" XP animation anchored to the word appears immediately (no server round-trip) + a first-interaction highlight (`NewConstructsEvent`); the XP total updates locally before any sync. _(analytics-system.instructions.md; [flaky] [staging-only])_
- [ ] Block a construct whose XP removal would drop total below a level threshold — **Expect:** the displayed global level does NOT visibly decrease (an XP offset is applied); the blocked construct disappears from all analytics views, stops contributing XP, and is excluded from practice (persists across sessions). Don't assert "XP dropped by exactly N". _(analytics-system.instructions.md; [gated] [staging-only])_
- [ ] Cross the next level threshold (e.g. a correct practice answer) — **Expect:** a full-screen level-up banner + chime (`LevelUpEvent`), an AI-generated summary of what was learned since the last level-up, and the cluster XP ring resets toward the next level. _(analytics-system.instructions.md; routing.instructions.md; [flaky] [gated] [staging-only])_

### Standalone practice (Pro)

- [ ] Tap "Practice Vocab" (active subscription, enough recorded vocab uses) — **Expect:** a right-column `practice` panel (bounded card, not a route/fullscreen) runs ~10 vocab exercises from weakest words, mixing lemmaAudio + lemmaMeaning ~50/50; opening it closes the analytics master + any open vocab/grammar detail. _(practice-exercises.instructions.md; routing.instructions.md; [gated])_
- [ ] Tap "Practice Grammar" (active sub, recent grammar errors / weak morph) — **Expect:** fetches recent grammar errors first (grammarError targets) then fills with weak morph features (grammarCategory targets); ~10 shown. _(practice-exercises.instructions.md; [gated])_
- [ ] Advance through exercises while content is still loading — **Expect:** practice never blocks on network — selection is local; while content fetches the UI shows shimmer placeholders, NEVER a blocking spinner. (Wait for shimmer-to-content, not for a spinner to disappear.) _(practice-exercises.instructions.md; [flaky])_
- [ ] Click the practice panel's X mid-session (unanswered exercises remain) — **Expect:** closing confirms first (unsaved-progress prompt); a completed/errored session does NOT re-prompt; abandoning by opening analytics from the cluster does NOT prompt (that path just replaces the right column). _(routing.instructions.md; [gated])_
- [ ] Answer an exercise incorrectly — **Expect:** a wrong answer still records a construct use and the session advances (completion, not perfection — wrong answers contribute at reduced XP). _(practice-exercises.instructions.md; [gated])_
- [ ] Answer the final target — **Expect:** `CompletedActivitySessionView` shows total correct/incorrect/skipped, time elapsed (bonus XP if under 60s), and a per-item review. _(practice-exercises.instructions.md; [gated])_

### Message practice (toolbar 💪)

- [ ] Open Message Practice on an L2 message with multiple practiceable tokens — **Expect:** only `saveVocab=true` tokens become targets (punctuation/numbers excluded), deduplicated by lemma ("running"/"runs" → one), capped at 5 targets per activity type per message. _(practice-exercises.instructions.md; [gated])_
- [ ] Complete every word in one mode (listening / wordMeaning / wordEmoji / wordMorph) — **Expect:** the mode's toolbar icon turns gold. _(practice-exercises.instructions.md; [gated])_
- [ ] Reopen Message Practice for the same message within the 1-day TTL — **Expect:** targets are deterministic — the same targets for a given eventId+language+token set (no randomness on re-render); cached per message, 1-day TTL. _(practice-exercises.instructions.md)_
- [ ] Submit a correct answer for a word — **Expect:** TTS plays on the correct answer for audio reinforcement. _(practice-exercises.instructions.md; [flaky])_
- [ ] Complete an emoji and/or meaning choice for a lemma, then open its word card / analytics — **Expect:** emoji + meaning choices persist beyond the session as the user's personal annotation (visible in word cards + analytics); every answer produces a `ConstructUseModel` feeding the vocabulary garden / XP. _(practice-exercises.instructions.md; [gated])_

---

## Accessibility (cross-journey)

- [ ] Inspect the cluster controls (avatar, each tracker, level medal, flag) via the accessibility tree — **Expect:** every element exposes a semantic button label + tooltip (canvas has no implicit labels): avatar names "profile/settings", trackers name their metric, the flag names the learning-settings shortcut. _(routing.instructions.md; accessibility.instructions.md; [staging-only])_
- [ ] Tab through learning-settings controls with keyboard only, change a value, save — **Expect:** every interactive control is reachable + triggerable by keyboard, focus always visible, focus never trapped. axe cannot prove this — required manual pass. _(accessibility.instructions.md; [manual])_
- [ ] Zoom the browser to 200% and review the analytics panel + color-coded grammar tags — **Expect:** text survives zoom/resize, contrast is sufficient, nothing (e.g. proficiency on grammar tags) is conveyed by color ALONE (a non-color indicator exists). axe is blind to canvas pixels — manual contrast/zoom review. _(accessibility.instructions.md; [manual] [grammar])_

---

## State matrix (variations to sample)

Expand each journey over these axes. Sample the branches carrying real logic first: **subscription, lock, joined/unjoined** before cosmetic variations.

| Axis | Variations to sample |
|------|----------------------|
| **Auth** | logged out → chooser; logged in + L2 set → workspace; logged in, no L2 → `/registration`; returning user (keychain hint) vs fresh device |
| **Subscription** | free + account >7 days (paywalls fire); new user <7 days (trial window — everything unlocked); active web/Stripe sub; cross-platform sub (management blocked); promotional / lifetime |
| **Progression** | first Mission (always unlocked) vs later gated Mission (locked); below vs at/above star threshold (default 10 vs teacher override); cross-course unlock; fail-open cold link |
| **Membership** | discovered (not joined) vs joined; knock-pending vs approved; previously-left space; admin (power 100) vs non-admin |
| **Data** | empty (new joiner, 0 stars, no morph constructs, empty viewport) vs populated; offline / CMS-unreachable fallback; stale-cache (1-day TTLs) |
| **Language** | L1 vs L2 vs unknown-language message; single-flag vs region-ambiguous L2; regional-variant vs base in pickers; L1 with vs without grammar-construct-meanings rows |
| **Layout** | wide two-column (>~833px) vs single-column (≤~833px); panel master/detail fold/unfold; bottom-sheet (narrow map content); cold-link leaf fallback vs live recency |

---

## Known gotchas

Read before judging a finding — most are false-negative traps where correct behavior looks like a bug.

- **World-map tile-render gates the semantics tree.** On the world map the entire semantics tree stays at **2 nodes** until map tiles render, and `flutter_map` defers rendering until it gets a pointer interaction on its canvas (flutter#175465). A fresh navigate + long wait is not enough. **Wake it with a scroll on the map canvas at center `[700,400]` (screenshot-space), not on the nav bar** (2 → 52 nodes). An empty / 2-node tree is the load race, NOT a missing feature — run the wake-and-poll recipe before asserting absence. _(agent-browser-qa SKILL)_
- **Two model docs disagree.** `layout.instructions.md` still describes the legacy GoRouter `/rooms` tree + a hardcoded 833px breakpoint, while `routing.instructions.md` + `routes.dart` describe the live token (`?left/?right/?m`) workspace that collapses the path to `/`. When a test fails, check which model the running build implements — `routes.dart` confirms the token model is live and legacy paths redirect. The ~833px number is still operative.
- **Camera re-framing is debounced (~2s settle, `_fitSettleDelay`).** A deliberate move (search result, tapped pin) glides immediately; layout-driven re-framing waits. Assert on the FINAL settled framing, not intermediate frames, or screenshots are timing-flaky.
- **Large-card rotation is a 5s wall-clock timer that only ticks with >3 eligible.** Hold still ~10–15s with >3 joinable/unlocked items in view to observe rotation; with ≤3 it is intentionally static (looks like a no-op).
- **Open-session discovery is limited to JOINED courses today.** The map-wide open-session backend endpoint is deferred — green/joinable pins for non-joined courses simply won't appear. That's expected, not a bug. "Pinged" (hand glyph) is best-effort (scans recent messages, no persistent state) and can be absent/stale even when a host pinged.
- **The gate fails OPEN before it is built.** A cold-opened `/<UUID>` activity link may show Start enabled momentarily even for gated content; the locked state appears reliably only AFTER joined-course Mission sequences + star rollup load. Visit the course/map first to force the gate to build, or a "lock should appear" test false-passes.
- **Best-per-activity stars.** Replaying an activity does NOT add stars (`userStarsByActivity` keeps the max). To cross a threshold, spread stars across DIFFERENT activities under the same Mission — a double-complete-for-double-stars test fails by design.
- **One live view is destructive by design.** The Matrix timeline is shared, not reference-counted — opening a second live room/session overwrites the first. Test sequentially; a leftover open live view from a prior step silently drops.
- **Single shared cross-column detail slot.** vocab detail, grammar detail, completed-activity session review, and practice all share ONE slot — opening any one closes the others. Don't expect two details to coexist.
- **Trial-window inverts the obvious paywall test.** While `inTrialWindow` (account <7 days), `showSubscriptionGatedContent` is true → all gated features work and the paywall silently no-ops. To test locks you need an account >7 days old with no active subscription. `inTrialWindow` depends on `userSettings.createdAt` from the choreographer — gating can flip after load, so observe-then-settle.
- **Two paywall show paths with different guards.** `PaywallCard.show` (inline) checks the backoff-gated `shouldShowPaywall`; `SubscriptionPaywall.show` (bottom sheet, from gated `ErrorIndicator`s) only early-returns on empty products / gated-content-shown — it ignores backoff. Don't conflate them. Backoff is persisted in GetStorage; clearing site storage resets it.
- **Web price comes from RevenueCat metadata, not Stripe** — it can legitimately differ from the Stripe checkout price (documented gap), not necessarily a failure. `availableSubscriptions` is GetStorage-cache-first, so pricing/products can be stale across relaunches; an empty/stale catalog makes the bottom sheet silently not open.
- **Profile saves are async: write account data → wait for sync round-trip → stream dispatch → side-effects.** Assertions right after Save race the round-trip; poll until settled. Bot-option propagation retries 3× (5s→10s→20s backoff). The activity-room language-mismatch popup is rate-limited once / 30 min per room.
- **Bot-option eligibility keys off `pangea.activity_plan` state-event presence,** which persists after an activity ends — rooms with stale activity plans silently won't get option updates. Verify against the bot DM (DM-first is always covered), not an old activity room.
- **Analytics first-paint race.** The cluster, chat-list indicators, and analytics surfaces must read inside a `StreamBuilder` subscribed during BUILD; `AnalyticsUpdateDispatcher` fires its first update once during init on a hot broadcast stream with no replay. A surface subscribing after init shows stale/zero until the next live update — "zero on first load" can be a real bug OR a too-early read.
- **Public-profile level lags local `derivedData`.** Cross-check displayed level/XP against the LOCAL derivedData (cachedDerivedData fallback), not the public profile — they differ transiently. Blocking a construct / switching languages applies a hidden XP offset to prevent a visible level-down — don't assert raw XP math against the shown level.
- **Token-centric + lazy loading in the reading toolbar.** All word-level assistance needs a tokenized message — tapping before tokens resolve yields limited functionality (flaky if you open "immediately"). Translation/TTS/transcription fire only on mode activation — asserting a request on message tap falsely fails. First-click XP/underline is per-session — re-running in the same session won't reproduce it.
- **Web TTS has no quality field** — "known-good" is inferred from voice NAME patterns, and good web voices load asynchronously, so a too-early tap may route to backend. Availability varies by browser/OS (Safari vs Chrome). Backend TTS is entitlement-gated server-side (401 for free) — the free-vs-Pro branch is first and not reproducible without controlling subscription state.
- **Phoneme/heteronym routing reads the LOCAL PT v2 cache (cache-only, non-blocking).** If the PT response wasn't fetched (transcription not rendered), there's a cache miss and playback falls through to normal routing — trigger the transcription render first to seed the cache. The PT disk cache is 24h TTL; the stale-phonetics-refresh path needs an intentionally divergent local cache (hard to stage).
- **Writing assistance is debounced + LLM-nondeterministic.** Matches appear only after a typing pause + `/grammar_v2` round-trip — asserting ring/highlight immediately races the debounce. Which words flag, alt-vs-distractor coloring, and surface auto-apply depend on the live LLM and vary across runs/models — pin known-buggy inputs; treat exact counts/colors as staging-only and variable. Several ring animations are Future Work — assert end-state (color/opacity/position), not the transition.
- **Recently-changed surfaces may not match stale deployments.** `VocabDetailsView` phonetics (lemma-based, per-form audio removed), token-info-feedback v2, the writing-assistance ring, and legacy→token redirects are recent — an older deployment may still show the old behavior. Confirm the deploy landed before re-testing a fix.
- **Doc path drift.** Subscriptions instructions reference `lib/pangea/subscription/**` but code lives under `lib/features/subscription/**`; toolbar surfaces are token-driven overlays over `/` (there is no `/analytics`, `/settings`, `/chats` render route) — assert via tokens/UI, not path navigation. The reading toolbar / word card never change the URL.
- **Grammar/practice content can degrade legitimately.** Grammar-error practice fails to materialize when the original room isn't loaded (left room → `getRoomById` null); the toolbar scorer and the standalone simple-recency sort use different prioritization — don't assume identical target ordering. Empty/degraded grammar-error sessions are an expected branch.
- **Auth redirect race.** `PAuthGaurd` resolves `hasSetL2` asynchronously; on a cold load before `pController` is wired the guard uses only `client.isLogged()`. Tests hitting `/` or `/home` very early may see a transient login/world redirect before the L2-based `/registration` redirect resolves.
- **Staging auth + seeded data.** Live-app discovery, progression, knock/invite, analytics-room, invite_by_email, and subscription flows need a valid staging session + seeded joined-course progression / live sessions. Mark these staging-only; without seeded progression the gate fails open and pins may all appear unlocked.

---

## Graduation to Playwright

Agents own exploration + recently-changed areas (the unknown unknowns). Once a flow is **understood and stable** (deterministic oracle, mockable backend, no live-session/LLM nondeterminism), encode it as an [`add-e2e-coverage`](../.github/skills/write-e2e-test/SKILL.md) Playwright spec so CI guards it instead of re-discovering it each round. Track the two-tier split below; promote as flows stabilize.

**Ready to graduate (stable, deterministic, mockable):**

- Cross-cutting invariants per surface (no route exception / blank screen; back & close; loading/empty/error renders; semantic completeness) — the cheapest regression catches, deterministic with `mock=true`.
- Auth redirect gates — logged-out `/`→`/home`; logged-in + L2 → workspace; no-L2 → `/registration` (`p_vguard.dart` behavior).
- Legacy-path → token-URL redirects (`/chats`, `/courses`, `/settings`, `/profile`, `/analytics`, `/analytics/morph`, `/rooms/settings/subscription`, `/courses/!spaceid[/!roomid]`) — pure `legacy_redirects.dart` resolve(), no backend.
- Shareable / deep-link URL fidelity + refresh restoration (the URL is the single source of truth) — token round-trip, deterministic.
- Layout breakpoint behavior at ~833px (two-column ↔ single-column; rail ↔ bottom nav; fold/unfold; cold-link active-leaf fallback) — pure layout, viewport-driven.
- The first-class activity UUID route (regex matches only a UUID; `/home` never collides) and its `launch`/`roomid` param handling.
- Paywall gate presence on each gated surface (reading toolbar, practice, activity summary, phonetic transcription, word card) — assert the gated `ErrorIndicator`/`UnsubscribedPracticePage` renders with a free, >7-day account (mock subscription state).
- Language-list filtering (L2 = `l2Support != na`, L1 = all, course-creation excludes regional variants) + CMS-unreachable fallback to `LanguageConstants.languageList`.
- Fail-open on a bare `/<UUID>` cold link (Start enabled, no course context) — deterministic.
- Semantic-label audit of the cluster controls (every control named) — axe-core / read_page assertion.

**Keep agent-only for now (live, nondeterministic, or staging-seeded):**

- Anything `[staging-only]` requiring a real Synapse round-trip: knock/approve/auto-join (KnockTracker sync timing), invite_by_email, analytics-room access, cross-device KnockTracker.
- Star rollup → next-Mission unlock and teacher-overridden thresholds (needs seeded joined-course progression + awarded-goal room state + debounced re-gate).
- Joinable/green session pins (time-sensitive open sessions, only in joined courses).
- Writing-assistance match content + span-card choices (live LLM nondeterminism, debounce, Future-Work animations).
- Word-level TTS device-vs-backend routing (browser/OS voice variance, entitlement gating, phoneme cache seeding).
- Analytics first-paint stream timing, level-up celebration, level-protection XP offset, instant-XP animation.
- Real Stripe checkout / billing-portal redirects and post-payment recognition (external, async, env-dependent).
- Large-card rotation + camera-settle timing (wall-clock + debounce).
- Manual a11y passes (keyboard-only operability, contrast/zoom, screen-reader announcement) — outside axe's reach.
