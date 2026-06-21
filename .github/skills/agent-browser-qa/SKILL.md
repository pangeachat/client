---
name: agent-browser-qa
description: >-
  Running automated, exploratory browser QA of the Flutter web client with AI agents
  driving the Claude-in-Chrome extension (not scripted Playwright). Use when asked to
  "run agent QA", "test the deployed/staging app with agents", "have agents click through
  the app", "drive the canvas by semantics", or whenever an agent reports an empty /
  2-node semantics tree and can't find on-screen elements. Owns the canvas-driving recipe
  (the map-tile-gated semantics race + wake-and-poll), the single-browser round structure,
  and the dead-ends that DON'T work. For SCRIPTED Playwright/axe coverage use
  `add-e2e-coverage` instead.
---

# Agent-driven browser QA — Flutter web client

This is exploratory QA where an **AI agent operates the live app** through the Claude-in-Chrome MCP (`mcp__Claude_in_Chrome__*`), finds bugs, and reports them. It is **not** the scripted Playwright suite — for deterministic specs + axe-core a11y audits, use the [`add-e2e-coverage`](../write-e2e-test/SKILL.md) skill and read [`playwright-testing.instructions.md`](../../instructions/playwright-testing.instructions.md). This skill owns the part that repeatedly burns sessions: getting the canvas to be driveable at all, and structuring a round.

Env setup, restart, local↔staging switching, and login creds live in [`run-flutter-web-local`](../run-flutter-web-local/SKILL.md) — do not duplicate them; read that first if you need a server or to point local at staging.

## The one thing that wastes the most time: the semantics tree is load-gated

The client renders to a single `<canvas>` (CanvasKit). Agents drive it through Flutter's **accessibility semantics tree**: `read_page(filter:"interactive")` returns elements by role+name with `[ref_N]`, and you click/`find` by ref/name. Without the tree, agents fall back to screenshots + pixel clicks (unreliable). Enabling the tree (`ENABLE_SEMANTICS=true` locally / stamped on staging) is necessary but **not sufficient**.

**The trap (diagnosed empirically, 2026-06):** on the **world map**, the entire semantics tree stays at **2 nodes** — even standard widgets that are visually on screen (search box, level chips, nav buttons) are absent from the tree — until the **map tiles finish rendering**. And the `flutter_map` widget **defers rendering until it receives a pointer interaction on its canvas** (matches [flutter/flutter#175465](https://github.com/flutter/flutter/issues/175465): semantics init delayed until first user interaction). So:

- A fresh navigate + a long wait is **not enough** — a probe once waited 43s and stayed at 2 nodes because the map never rendered.
- The interaction must land **on the map canvas**, not the nav bar. Clicking a left-nav icon at `[60,197]` did **not** wake it; a scroll at the map center `[700,400]` did (2 → 52 nodes instantly).
- **An empty / 2-node tree is the load race, NOT a bug.** Never let an agent report a feature "missing" or "broken" because `read_page` came back empty. That is the single most common false finding. Confirm the tree is built first.

### The wake-and-poll recipe (do this on every screen showing ≤2 nodes)

```
1. count = javascript_tool: document.querySelectorAll('flt-semantics').length
2. if count <= 2:
   - computer scroll at [700,400] (map center, screenshot-space coords), direction "up", amount 3
   - computer wait 6s
   - re-check count;  repeat the scroll up to ~3x until count > 15
3. confirm: document.querySelector('flt-semantics[aria-label="flutter_map"]') exists on the map
4. NOW read_page(filter:"interactive") and drive by ref / find-by-name
```

- Coordinates passed to `computer` actions are **screenshot-space** (the screenshot comes back ~1478×812 even though `read_page` reports a smaller CSS viewport). `[700,400]` is the map center at that size.
- **Do NOT poll with an in-page `setInterval`/`await` loop.** A backgrounded/unfocused tab throttles timers, the `Runtime.evaluate` CDP call hangs, and you get `CDP sendCommand "Runtime.evaluate" timed out after 45000ms`. Poll from **outside**: alternate `computer wait` + a one-shot `javascript_tool` count.
- **If the tree is still ≤2 nodes after ~3 wake attempts:** screenshot to confirm the map actually rendered visually. If pixels are present but the tree is empty, the gate didn't lift — hard-reload once (generic CDN-cache fallback), re-run the recipe once, and if still stuck **STOP and report** "semantics tree never built on &lt;screen&gt;; could not drive" as a **tooling blocker, not a product bug**. Do not pixel-click through the round, and do not report features as missing.
- On non-map sub-screens (course panel, activity, chat, settings) the gate is usually just timing — wait ~5s and re-check; if stuck ≤2, one small scroll/click on a neutral area wakes it.
- Debug builds (local) populate more eagerly than the deployed `--profile` build, but the map-tile gate can still apply — run the recipe **defensively** anywhere the tree is empty.

## What does NOT fix it (so future sessions skip the dead-ends)

These were all chased and **ruled out** — don't repeat them:

- **`--force-renderer-accessibility` Chrome relaunch — NO EFFECT.** Tested both directions in Playwright (`--force-renderer-accessibility` AND `--disable-renderer-accessibility`): the tree built either way. The renderer-accessibility flag is not the lever. Do not quit/relaunch the user's Chrome for this.
- **Chrome version — not it.** The tree builds on Chromium 145, 147, and 149. A newer/older Chrome is not the cause.
- **AWS / staging creds — not needed** to diagnose. (They're only needed to run the *Playwright* suite logged-in; the saved `e2e/.auth/user.json` goes stale and silently lands on the logged-out screen.)
- **The deployed `--profile` build is fine.** Playwright reads a populated tree on it without any flag; the gap was always the wake interaction + tile render, never the build mode. Do not switch staging to a debug build.
- Why Playwright "just works" but the extension needs the wake: Playwright's Chromium loads with accessibility engaged and its locators tick the engine; the live extension-driven Chrome needs the explicit canvas interaction. Same underlying #175465 deferral.

## Structuring what to test — building a robust, resilient checklist

Don't free-style the flows. A checklist is **robust** (finds real bugs) and **resilient** (survives app changes) when it's built this way:

1. **Derive from contracts, not memory.** The client `CLAUDE.md` indexes ~30 feature docs (`world-map`, `quests`, `activities`, `course-plans`, `subscriptions`, `routing`, …); `lib/config/routes.dart` + [`routing.instructions.md`](../../instructions/routing.instructions.md) define every reachable surface/panel. Each doc is the **oracle** — its stated behavior is the item's *Expect* line. Generating items from docs+routes makes them traceable: when a feature changes its doc changes and the item follows.
2. **Organize by journeys, not screens.** The expensive bugs live at the seams (the `What now?` `GoException`, the LO-lock gate). A journey is an end-to-end path with checkpoints: discover-on-map → join course → start activity → bot interaction → complete → stars/progress → unlock next.
3. **Expand each journey over a state matrix.** Same flow, different behavior by: auth (new vs returning), subscription (free vs Pro paywall), progression (locked vs unlocked), membership (joined vs discovered), data (empty vs populated), language (L1/L2), layout (column vs single-panel). Sample the branches that carry real logic first (subscription, lock, joined/unjoined).
4. **Append cross-cutting invariants to every surface** — the cheapest regression catches: no route exception / blank screen; back & close work and don't orphan state; loading/empty/error states render (not an infinite spinner or raw error); semantic/a11y completeness (every control named); responsive (column vs single). Fixed list, applied everywhere.
5. **Make each item falsifiable + tagged.** Item = `{surface or journey, precondition state, action, Expect (cite the doc), tags}`. Tags: `[staging-only]`, `[recently-changed]`, `[gated]`, `[flaky]`. The cited *Expect* turns "is this a bug?" into a clean yes/no; tags drive ordering (recently-changed + money/data paths first).
6. **Guard the two app-specific false-negatives** in every item's judgment: confirm the tree is built before asserting absence (see the wake recipe); distinguish **gated** (subscription / lock / role) from **missing** before reporting.
7. **Keep it living; graduate stable flows to Playwright.** The repo already runs a coverage-matrix pattern for scripted tests ([`e2e/web-and-accessibility-next-steps.md`](../../../e2e/web-and-accessibility-next-steps.md) + `e2e/trigger-map.json`). Agents are for exploration + recently-changed areas (the unknown unknowns); once a flow is understood and stable, encode it as an `add-e2e-coverage` Playwright spec so CI guards it instead of re-discovering it each round. Track which flows are agent-only vs scripted — that two-tier split is what keeps coverage durable.

**Where it should live.** The process above wants a single **living checklist in the repo**, regenerated as features ship and each found bug becomes a regression item — proposed home `client/e2e/agent-qa-checklist.md`, beside the Playwright coverage matrix. Until that exists, rounds use the per-round tmp file (see "Where the flow checklist lives" under Running a round).

## Running a round

**First: attach to the right tab.** Run `list_connected_browsers`; if zero, ask the user to connect Claude-in-Chrome — do **not** fall back to computer-use pixel-driving the whole app. Then `tabs_context_mcp` to list tabs, pick the one whose URL matches the target (`app.staging.pangea.chat` or `localhost:8090`), select it, and bring it to the **foreground** before driving — a backgrounded tab throttles timers and is what hangs `Runtime.evaluate` (see the wake recipe). Pass the resolved tab id into the agent prompt.

**Single-browser constraint.** There is normally **one** connected browser (`list_connected_browsers`) with one or few tabs. **Do not run parallel agents against one browser** — they stomp each other's navigation/clicks. Either one agent owns the browser for the whole round, or serialize (one at a time). If the main loop spawns a background QA agent, the main loop must then **stay off the browser** until it returns.

**Target.** Decide deployed-staging vs local explicitly and tell the agent:
- Deployed staging `https://app.staging.pangea.chat` — the real artifact; this is where **staging-only** bugs surface (e.g. a route/`GoException` that only fires on the deployed build). Semantics is stamped on (driveable as-is). `/.env` is served `no-cache, must-revalidate` (per `main_deploy.yaml`), so config propagates every deploy — no stale-config workaround needed; if anything looks cached, a one-off hard-reload is the generic CDN fallback.
- Local `http://localhost:8090` (debug, against local or staging backends) — faithful proxy, fastest fix-verify loop. Set `ENABLE_SEMANTICS=true` in `client/.env` + clean-restart (see `run-flutter-web-local`).
- **Deploy lag:** a just-merged fix is **not** on staging immediately — `main_deploy.yaml` must finish (a few minutes). Before re-testing a pushed fix, confirm the deploy completed (Actions run / staging health) and hard-reload once. Re-testing too early against the old build is a known source of false "still broken" reports.

**Where the flow checklist lives.** Don't invent flows — pull them from the checklist (see "Structuring what to test" above for how it's built). The curated round checklist currently lives at `~/PangeaChat/tmp/qa-<round>-YYYY-MM-DD.md` (e.g. `qa-world-redesign-2026-06-21.md`); prior rounds (`qa-prod-*.md`) are templates. Read it, take the web-applicable items (drop `[iOS]`/`[Android]`/`[iPad]`-only ones), and paste them + their **Expect** lines into the prompt as the flows to exercise. If no current file exists, copy the newest to a new dated file and prune to this build. (Reporting still comes back to the requester per **Reporting** below — ignore the checklist's own "file a GitHub issue" line.)

**Agent prompt must include:** the target URL + tab id + that it's already logged in (don't log out); the **wake-and-poll recipe verbatim**; the rule that an empty tree ≠ a bug; the specific flows to exercise; the semantic-gap audit ask; and the guardrails below.

**Bypass paid backends with `mock=true`** on the client's choreographer requests (+ `mock_llm_latency_override_s=0`) so a round is economical — see [`playwright-testing.instructions.md`](../../instructions/playwright-testing.instructions.md) § Bypassing paid backend calls.

**Guardrails on a live session** (the round runs against a real logged-in account): no irreversible/destructive actions — no deleting rooms/courses, no leaving courses, no sending real chat messages to **other humans**, no changing account settings. Starting activities and interacting with the **bot** (`@bot:staging.pangea.chat` on staging) are fine.

**Bounding a round.** Scope each round — give the agent a flow subset (e.g. one checklist section) or a soft step/time budget, and have it report findings-so-far when the budget is hit rather than starting new areas. Prefer several scoped rounds over one open-ended sweep; long sessions degrade and lose the wake-state context. Between rounds, close MCP-created tabs you opened (`tabs_close_mcp`) so the next round's `tabs_context` is unambiguous; leave the user's original app tab open and logged in.

**Reporting.** Findings come **back to the requester** (functional bugs + semantic/a11y gaps), each with screen, repro, expected vs actual, severity, screenshot id if visual. **Do not file GitHub issues** unless explicitly asked — the team's flow for QA-found bugs is fix-and-push to staging. **Verifying a fix:** check it locally first (`localhost:8090` debug, fastest loop — see `run-flutter-web-local`), then confirm on deployed staging **after the deploy lands** (see Deploy lag), since some bugs are staging-only (route/`GoException` on the `--profile` build). A fix that passes locally but not on staging is not done. Semantic-gap audit = list controls that `read_page` shows as `button [ref]` with **no name**, icons without accessible names, role-without-label, unlabelled images; these break screen readers and Playwright equally (see widget-testability rules in `playwright-testing.instructions.md`).

## Living document

This skill is meant to accrue hard-won recipe over time. When a round teaches you something — a screen with its own wake quirk, a flow that only breaks on staging, a new dead-end, a better trigger than scrolling — **add it here** in the same empirical voice ("diagnosed …, on <date>"). The point is that the next session never re-loses the time this one spent.

### Changelog

- **2026-06-21** — Initial. Root-caused the "deployed app isn't driveable" wall to the map-tile-gated, interaction-deferred semantics tree (#175465); established the wake-and-poll recipe; ruled out the renderer-accessibility flag, Chrome version, and build mode.
- **2026-06-21** — Hardened via adversarial review: added tab-attach startup, the stuck-recipe escape hatch, deploy-lag + fix-verification, and round bounding; added the "Structuring what to test" checklist methodology; corrected the `/.env` state (no-cache fix now merged to `main`).
