---
name: run-flutter-web-local
description: >-
  Starting and restarting the Flutter web client locally without the recurring
  startup hang. Use to bring :8090 up from scratch, when the app sits forever on
  the loading spinner, when a code change isn't showing up, when port 8090 is
  dead, or when stray flutter/dart compilers have piled up. Covers the clean
  first-time startup procedure, the one-tab IndexedDB rule, the fifo control
  channel, hot-reload vs clean-restart, and stuck-state recovery.
---

# Local Flutter web dev — startup & restart

The client runs as `fvm flutter run -d web-server --web-port=8090` and is viewed in an **external** Chrome (the Claude-in-Chrome extension), not a Flutter-launched Chrome. The broader stack (Synapse, Choreographer, CMS, bot) is managed by the `pangea-local-setup` control plane (`local-dev/pangea`); this skill is the Flutter-specific nuance that control plane does not solve.

> **Toolchain (do this first, every time).** The repo pins **Flutter 3.41.4** via `client/.fvmrc`, and CI hard-fails if `.fvmrc` disagrees with `.github/workflows/versions.env`. A bare `flutter` is whatever is global on the machine (often a *different* version → a build that doesn't match what ships, and subtle breakage). **Run everything through the pinned toolchain: `fvm flutter …` / `fvm dart …`.** fvm lives at `~/.pub-cache/bin` — if it's not on PATH, prefix `export PATH="$HOME/.pub-cache/bin:$PATH"`. If fvm is missing entirely: `dart pub global activate fvm && (cd <repo>/client && fvm install)`.

## First-time startup (the clean path)

Do these in order. It gets you to a loaded, logged-in map without the flailing.

**1. Is something already on :8090? Don't trust it blindly — verify it's *your* checkout, branch, and SDK.** A stale serve from another git worktree (or the global Flutter version) is the #1 time-sink: it looks up, but it's the wrong code.

```bash
curl -sf -o /dev/null -w "8090: %{http_code}\n" --max-time 2 http://localhost:8090/ || echo "8090 free"
# If up, see which checkout + Flutter version it is actually serving. The running
# compiler (frontend_server) carries both as its --packages path and a -D define,
# so grep them straight out of the command lines:
ps -eo command | grep -oE "[^ ]*/\.dart_tool/package_config\.json|FLUTTER_VERSION=[0-9.]+" | sort -u
#   want: .../<your-checkout>/.dart_tool/...  AND  FLUTTER_VERSION=3.41.4
git -C <repo>/client branch --show-current   # is the checkout on the branch you want?
```

Matches your checkout + branch + 3.41.4 → reuse it. Anything off → clean-restart (step 2-3).

**2. Ensure the single fifo holder** (so we can send `r`/`q` from other shells). See [The fifo control channel](#the-fifo-control-channel) for why; the snippet:

```bash
[ -p /tmp/f8090 ] || mkfifo /tmp/f8090
HPF=/tmp/f8090.holder
if ! { [ -f "$HPF" ] && kill -0 "$(cat "$HPF" 2>/dev/null)" 2>/dev/null; }; then
  ( exec 3<>/tmp/f8090; exec sleep 2147483647 ) & echo $! > "$HPF"
fi
```

**3. Launch one clean run** and wait for the banner:

```bash
cd <repo>/client
export PATH="$HOME/.pub-cache/bin:$PATH"
: > /tmp/flutter_run_8090.log
nohup sh -c 'export PATH="$HOME/.pub-cache/bin:$PATH"; fvm flutter run -d web-server --web-port=8090 --web-hostname=0.0.0.0 < /tmp/f8090 > /tmp/flutter_run_8090.log 2>&1' >/dev/null 2>&1 &
# wait for it to serve:
for i in $(seq 1 50); do curl -sf -o /dev/null --max-time 2 http://localhost:8090/ && { echo "serving ~$((i*3))s"; break; }; sleep 3; done
```

**4. Open EXACTLY ONE tab on `http://localhost:8090/`. This is an invariant, not hygiene.** The Matrix client store is **IndexedDB with no cross-tab coordination** (no `onblocked`/`versionchange` handling in the SDK, no BroadcastChannel/web-locks). A second tab — or a *zombie/frozen* tab still holding a connection — can make `client.init()`'s database open **block forever** during any version upgrade/migration: the app sits on the spinner with the renderer responsive but no first frame and no network. Before opening a fresh tab, close every other Pangea Chat tab.

**5. Expect a ~30s loading spinner on first paint, and DO NOT reload during it.** A debug web build serves ~2792 individual DDC module scripts; the first paint legitimately takes ~30s. A full browser reload **restarts the whole 2792-module fetch from scratch** (the dev server doesn't honor conditional GETs, so nothing is cached across full reloads) — reloading an in-progress load is how a 30s startup becomes 10 minutes. Let it finish once.

**6. Log in.**
- **A session already exists** → just load `http://localhost:8090/` (plain); it restores and lands on the map.
- **Logged out / fresh** → `http://localhost:8090/?devlogin=1` signs straight into the `.env` test account, skipping the canvas login form. Debug-only; see [Login](#login).

**7. Confirm the env points where you intend** (see [Env](#env--which-stack-the-build-talks-to)).

## "I just want to SEE it working" (no code edits) — the fastest path

A debug run is for *editing code* (hot reload). If you only need to look at / click through the app, a **profile build served statically** paints in seconds (dart2js → one bundle + ~50 deferred chunks, not 2792 DDC modules) and caches correctly across reloads:

```bash
cd <repo>/client
fvm flutter build web --profile --pwa-strategy=none --source-maps   # mirrors the deploy build
cp .env build/web/.env            # REQUIRED: on web the app fetches /.env over HTTP; rebuild wipes it
python3 -m http.server 8090 --directory build/web   # or: npx serve build/web -l 8090
```

Trade-off: **no hot reload**, and **`?devlogin=1` does NOT work** in a profile/release build (it's gated on `kDebugMode`). Log in once through the real canvas login form using the `.env` `TEST_MATRIX_*` creds against your `SYNAPSE_URL` (the session then persists across reloads).

## Narrow / mobile (single-column) mode in the extension browser

The Claude-in-Chrome extension cannot put the app below the 840px single-column
breakpoint on the usual path: `resize_window` shrinks the OS window but Chrome's
**per-host page zoom** keeps `window.innerWidth` large, and zoom shortcuts sent
via CDP never reach the browser chrome. Two pieces, both required:

1. **A fresh host origin resets zoom to 100%.** Serve (or just open) the app on
   `127.0.0.1` instead of `localhost` — zoom is keyed on the host, so the new
   host starts at 100% and `resize_window` then maps 1:1 to logical pixels
   (`resize_window(500, …)` → `innerWidth == 500` → single-column).
2. **Use a profile build served statically, not the debug server.** On the new
   origin the debug (DWDS) bootstrap tends to fail its websocket handshake — all
   ~2.8k modules load and `main()` never runs (spinner forever, no network, no
   errors). The profile build has no DWDS and paints in seconds:

```bash
fvm flutter build web --profile --pwa-strategy=none
cp .env build/web/.env      # REQUIRED — see the profile-build section above
python3 -m http.server 8091 --directory build/web
# → navigate the extension tab to http://127.0.0.1:8091/ and resize_window to phone size
```

The new origin has its own IndexedDB (no session): log in once through the real
form (`?devlogin=1` is debug-only). The session then persists across rebuilds —
`build` replaces `build/web` so re-`cp` the `.env`, but the origin's storage
survives.

**Cache-bust after every rebuild.** Chrome happily serves the PREVIOUS
`main.dart.js` from HTTP cache against `python3 -m http.server`, so a plain
reload can silently show the old build — you will "verify" a fix that never
loaded. Load `http://127.0.0.1:8091/?v=<timestamp>` (any fresh query string on
the top-level URL) after each rebuild.

## Iterating on code — hot reload vs clean restart

**Prefer hot reload `r` over refreshing the browser.** Hot reload keeps the loaded modules AND the logged-in session; only a full browser reload triggers the ~30s 2792-module re-fetch. `printf 'r' > /tmp/f8090`. This is the single biggest speedup for the edit loop.

### Watch on save

A file watcher can automate the `r` trigger so every `.dart` save sends a hot reload without a manual step:

```bash
# Requires fswatch (brew install fswatch)
cd <repo>/client
fswatch -o lib | while read -r _; do
  printf 'r' > /tmp/f8090
  echo "hot reload triggered"
done
```

Run this in a separate terminal while `flutter run` is up. It watches the whole `lib/` tree and fires `r` on any change. **Subject to the same DWDS reliability ceiling as manual `r`:** when the log shows `received 0/1 responses`, the watcher is running but the change didn't land — the DWDS connection is stale. Do a clean restart (see below) to refresh it; the watcher then works again for the next batch of saves.

**But `r`/`R` are unreliable over external Chrome (the DWDS trap).** Both `r` (hot reload) and `R` (hot restart) need a live DWDS (Dart debug) websocket to the browser. With the *external* extension Chrome that connection is frequently stale (attached to a previous/killed run, or the tab slept), so both time out with `received 0/1 responses`. Tell-tale: `grep "received 0/1 responses" /tmp/flutter_run_8090.log`.

- `r` on a stale connection fails **harmlessly** (server stays up) but your change didn't land. It also can't apply **structural** changes (new enum value, route-tree change, new top-level file, `const`/generic) — those silently no-op. When `r` doesn't take, do a clean restart.
- **Never send `R`** in this setup: on a stale connection its timeout **kills the `flutter run` process** (port 8090 goes dead). Prefer a clean restart over `R` entirely.

### Clean restart (the reliable path, ~10–20s warm)

```bash
cd <repo>/client
export PATH="$HOME/.pub-cache/bin:$PATH"
printf 'q' > /tmp/f8090                              # graceful stop — no orphaned compiler
for i in $(seq 1 15); do curl -sf -o /dev/null --max-time 1 http://localhost:8090/ || break; sleep 1; done
for pid in $(pgrep -f "web-server.*8090"); do kill -- -$(ps -o pgid= -p "$pid" | tr -d ' ') 2>/dev/null; done   # kill strays by GROUP
: > /tmp/flutter_run_8090.log
nohup sh -c 'export PATH="$HOME/.pub-cache/bin:$PATH"; fvm flutter run -d web-server --web-port=8090 --web-hostname=0.0.0.0 < /tmp/f8090 > /tmp/flutter_run_8090.log 2>&1' >/dev/null 2>&1 &
```

Then open **one fresh** tab on `http://localhost:8090/` (a hard reload of the existing tab races the dev-server boot → old bundle or blank canvas; a CDP screenshot of a mid-boot tab can wedge the connection). List with `tabs_context_mcp`, `tabs_create_mcp`, `navigate` the new tab, then `tabs_close_mcp` the old ids **after** the new tab is driving (closing the old tab first drops the group's active-tab reference and the next `navigate` fails). Never `flutter clean` just to pick up a code change — that forces a cold build (minutes).

## Recovery triage — "it's stuck"

| Symptom | Cause | Fix |
|---|---|---|
| Spinner forever, renderer **responsive**, no network, no console errors | **Browser-side**: an extra/zombie tab holds the IndexedDB lock, or a stale session is wedged | Close **all** :8090 tabs → open exactly one. If still stuck, clear site data for localhost:8090 (DevTools → Application → Clear site data) and reload one tab. A dev-server restart does **NOT** help — the wedge is browser-side. |
| Spinner forever after `?devlogin=1` specifically | (historical) devlogin racing session restore | Fixed in code (devlogin now waits for restore to settle and only signs in from logged-out). Recovery if seen on an old build: load plain `http://localhost:8090/`. |
| Port 8090 dead / `received 0/1 responses` in the log | **Server-side**: killed run (often from `R`) or stale DWDS | Clean restart (above). |
| `flutter run` takes minutes / goes cold | zombie compiler competing, or `.dart_tool` lock | Zombie recovery (below); `flutter clean` only as a last resort. |

## The fifo control channel

The dev server reads stdin from a FIFO so we can send it `r`/`q` from other shells:

```bash
[ -p /tmp/f8090 ] || mkfifo /tmp/f8090
# Keep ONE writer holding the fifo open, or flutter's stdin hits EOF and it quits
# right after serving (banner, then nothing on 8090). Two rules:
#   • open it READ-WRITE (`<>`), not write-only — a RW holder never EOFs and never blocks.
#   • reuse the existing holder via a pidfile (the snippet in step 2). Do NOT guard on
#     `pgrep -f sleep` (stale holders make that match and skip creation), and do NOT spawn
#     a fresh holder every launch (they pile up as orphaned `sleep` processes).
```

Send `printf 'r' > /tmp/f8090` (hot reload) or `printf 'q' > /tmp/f8090` (quit). One holder + one `flutter run` only. Orphaned `sleep 100000000` holders from the old write-only pattern are harmless; clear them with `pkill -f 'sleep 100000000'` while no client is running.

## Zombie recovery (wedged build / compiler pile)

`kill -9` of the `flutter run` parent orphans its `frontend_server`/`dartaot` child; orphaned compilers pile up, hold the `.dart_tool/` build lock, and starve CPU so the next run hangs. Always stop via `q`. To clear a pile:

```bash
ps -eo pid,ppid,etime,command | grep -iE "web-server|frontend_server|dartaot" | grep -v grep   # see them
for pid in $(pgrep -f "web-server.*8090"); do kill -- -$(ps -o pgid= -p "$pid" | tr -d ' ') 2>/dev/null; done   # kill trees by GROUP, not -9 the pid
```

There should be exactly **one** real `flutter run` (a `dartvm … flutter_tools` process) plus its single `sh -c` wrapper. More than one ⇒ kill the extras before starting.

## Env — which stack the build talks to

**Which Synapse / CMS / choreo the build points at is a per-service choice, not a package deal** — `client/.env` routes each independently, and mixing is normal (e.g. local Synapse + local CMS + staging choreo to smoke-test a deployed language tool). One hard rule constrains the mix: **`SYNAPSE_URL` and `CMS_API` must be the same environment** — the client authenticates to the CMS with the Matrix bearer token, and a cross-homeserver token gets **403** with course/activity content silently missing. `CHOREO_API` mixes freely. The full wiring, base-path shapes, and the other cross-service contracts that bite live in [local-stack.instructions.md](../../../../.github/.github/instructions/local-stack.instructions.md) — read it before debugging any "content not loading" symptom.

The web app fetches its config from `GET /.env` at the dev-server root (served from repo-root `client/.env`; no `assets/.env` since #6975). It is fetched once at app startup and the dev server caches it per process, so **neither a hot reload nor a browser reload picks up an edited `client/.env`** — clean-restart to serve the new values.

```bash
curl -s http://localhost:8090/.env | grep -E "SYNAPSE_URL|HOME_SERVER|CHOREO_API|CMS_API"
# Full local stack (pangea-local-setup): SYNAPSE_URL=http://localhost:8008 · HOME_SERVER=local.pangea.chat
#   · CHOREO_API=http://localhost:8002 · CMS_API=http://localhost:13134  (local CMS IS seeded from staging,
#     so it serves course/activity content — see the pangea-local-setup skill).
```

> `CMS_API` is the **host root** — the client appends `/cms/api/...` itself (`PayloadClient.basePath = "/cms/api"`), so do not include `/cms`. Only the **legacy** Synapse-only local setup (no seeded local CMS) leaves `CMS_API` at staging — and there, authed course content does not load. The full local stack uses `http://localhost:13134`.

`local-dev/pangea env` (the control plane) regenerates the localhost values via `lib/gen-env.sh`; land its output in `.env.local` (the local profile) and activate with `scripts/use-env.sh local`, then clean-restart so the new `.env` is served.

### Switching environments (local ↔ staging)

**Switch whole profiles, never individual keys.** `client/.env` is a generated copy of a per-environment profile — `.env.local` / `.env.staging`, both gitignored — switched by:

```bash
cd <repo>/client
scripts/use-env.sh local      # or: staging
# then clean-restart the dev server (it caches /.env per process)
```

**MUST READ** [matrix-auth.instructions.md](../../instructions/matrix-auth.instructions.md) for the profile rules (why `.env` is never edited in place, and the credentials each profile must carry).

Profile contents: **`CMS_API` must match the `SYNAPSE_URL` environment**: the client sends the Matrix access token as the CMS bearer and the CMS validates it against *its own* homeserver — a mismatched pair (local `@learner` token against staging CMS, or vice-versa) returns **403** and content silently fails to load.

| Key | `.env.local` | `.env.staging` |
|---|---|---|
| `SYNAPSE_URL` | `http://localhost:8008` | `matrix.staging.pangea.chat` |
| `CHOREO_API`  | `http://localhost:8002` | `https://api.staging.pangea.chat` |
| `CMS_API`     | `http://localhost:13134` *(host root; needs the full local stack)* | `https://api.staging.pangea.chat` |
| `HOME_SERVER` | `local.pangea.chat` | `staging.pangea.chat` *(or omit — it derives from `SYNAPSE_URL`: scheme stripped, leading `matrix.` dropped)* |
| `TEST_MATRIX_*` | the local `@learner` account | the shared `staging_automated_tests` account |

Source of truth for the staging routing values is the deployed client: `curl -s https://app.staging.pangea.chat/.env`. If a profile file is missing, seed it from the current `.env` plus that table. After switching, clean-restart and open a **fresh tab** — the dev server caches `/.env` per process, so a reload alone won't switch. Changing the homeserver invalidates the current session (stored per origin), dropping the app to onboarding/login — `?devlogin=1` signs into the profile's account. For back-and-forth work, prefer keeping staging on a **separate origin** (profile build on `127.0.0.1:8091`, the pattern below) so the two sessions' IndexedDB stores never invalidate each other. **Never point a local build at production.**

### Driving the app by semantics (Chrome extension)

The app renders to `<canvas>`, so the extension can only operate it by role+name once Flutter's accessibility semantics tree is on — otherwise it falls back to screenshots and positional clicks. Add `ENABLE_SEMANTICS=true` to `client/.env` and clean-restart to force the tree on from startup (off by default locally; it has a perf cost). **Staging** deploys force it on (`main_deploy.yaml`), so `app.staging.pangea.chat` is driveable by role+name too; **production** leaves it off. See [`playwright-testing.instructions.md`](../../instructions/playwright-testing.instructions.md). Note: a CDP screenshot or `read_page` against the **map** times out (`document_idle` never fires while map tiles keep loading) — use the macOS screenshot path, or wait for a non-map screen.

## Login

- **Local** (`local.pangea.chat`): `@learner` / `learnerpass`.
- **Staging** (`staging.pangea.chat`): the shared `staging_automated_tests` account — credentials in `client/.env` (`TEST_MATRIX_USERNAME` / `TEST_MATRIX_PASSWORD`) or AWS Secrets Manager. See [matrix-auth.instructions.md](../../instructions/matrix-auth.instructions.md).

**Skip the canvas login form: `?devlogin=1`** (debug builds only). The login form is canvas-rendered, so typing into it is the slowest part of a QA loop. Open `http://localhost:8090/?devlogin=1` (also works inside a hash route, `…/#/world?devlogin=1`) to sign straight into the test account using the `.env` `TEST_MATRIX_*` creds. It is **opt-in per load** (plain `localhost:8090` shows the real login flow, so that stays testable), uses the SDK's own login (always-valid session, unlike a stale `storageState`), and refuses production.

**It signs in only from a logged-out state.** `maybeDevLogin` waits for the stored session to finish restoring (it awaits the client's `roomsLoading`/`accountDataLoading`, the same futures `main()` awaits before `runApp`), then checks `isLogged()`: a restored session → no-op (load plain `/` to switch accounts, log out first); genuinely logged out → it signs in. Implementation: `lib/pangea/common/config/dev_login.dart`, invoked from `MatrixState.initState`.

> Historical note: an earlier version gated only on `isLogged()`, which is transiently false *during* restore, so it called `login()` on a half-restored client and froze the app on the spinner before first frame. If you hit a spinner-freeze on an old build, load plain `http://localhost:8090/`.
