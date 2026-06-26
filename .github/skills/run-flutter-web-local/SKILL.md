---
name: run-flutter-web-local
description: >-
  Running and RESTARTING the Flutter web client locally without the recurring hang.
  Use before you kill/restart the local dev server, when a code change isn't showing
  up in the browser, when port 8090 is dead, or when stray flutter/dart compilers
  have piled up. Covers the fifo control channel, clean-restart procedure, zombie
  recovery, and the local `.env`/Synapse-URL check.
---

# Local Flutter web dev — the restart procedure

The client runs as `flutter run -d web-server --web-port=8090` and is viewed in an **external** Chrome (the Claude-in-Chrome extension), not a Flutter-launched Chrome. That combination has three failure modes we hit repeatedly. This skill is the procedure that avoids all three. The broader stack (Synapse, Choreographer, CMS, bot) is managed by the `pangea-local-setup` control plane (`local-dev/pangea`); this is specifically the Flutter-restart nuance the control plane does **not** solve.

## The traps (diagnosed empirically)

**The root cause behind hot reload/restart pain: both `r` AND `R` over `-d web-server` need a live DWDS (Dart debug) websocket to the browser. With an *external* Chrome (the extension), that connection is frequently stale — it was attached to a previous/killed `flutter run`, or the tab slept — so both time out with `received 0/1 responses`. So in this setup, hot reload/restart is unreliable by default; the clean restart is the reliable path for ANY change.**

1. **`r` (hot reload) fails two ways.** (a) It cannot apply **structural changes** — a new enum value (e.g. a new `AppSection`), a GoRouter route-tree change, a new top-level file, a `const`/generic — those silently no-op and the app keeps running OLD code (looks "stuck"/wrong). (b) Even for a perfectly valid non-structural change, it **times out on a stale DWDS connection** (`Hot reload failed: TimeoutException … received 0/1 responses`, ~10s) and the change simply doesn't land. `r`'s timeout is non-destructive — the server stays up — but you're left thinking "my change didn't apply."
2. **`R` (hot restart) is a landmine — same DWDS dependency, worse outcome.** On a stale external-browser connection `R` gets the same `0/1 responses`, times out (~15s), **and the timeout KILLS the `flutter run` process** — port 8090 goes dead. This is the classic "I pressed restart and now nothing loads."
3. **`kill -9` of the `flutter run` parent orphans its compiler.** `flutter run` spawns a `frontend_server`/`dartaot` child. `kill -9 <parent>` (or `kill` followed too quickly by `-9`) leaves that child running. Orphaned compilers pile up, hold the build lock under `.dart_tool/`, and starve CPU — so the NEXT `flutter run` hangs or goes cold. This is the "lots of background dart processes" pile.

Tell-tale for a stale-DWDS timeout (either `r` or `R`): `grep "received 0/1 responses" /tmp/flutter_run_8090.log`. When you see it, stop retrying `r`/`R` — do a clean restart.

## The procedure

### Reflecting a code change in the browser

**Default to the clean restart (below) for ANY change.** It's ~10–20s warm and always works. In the external-Chrome setup, `r`/`R` are unreliable (stale-DWDS `0/1` timeout) so they're not worth the gamble most of the time.

`r` (hot reload) is only worth trying when **both** hold: the change is non-structural (widget body, style, string, method body — NOT an enum/route/new-file/`const`) **and** you have just reloaded the browser tab so its DWDS connection is fresh. Then `printf 'r' > /tmp/f8090`, reload the browser. If it stalls ~10s or the log shows `received 0/1 responses`, the change did NOT land — stop and do a clean restart. Never reach for `R` here (trap #2: its timeout kills the server).

### Clean restart (the reliable path, ~10–20s warm)

```bash
cd <repo>/client
# 1. Stop GRACEFULLY via the fifo — flutter shuts its child compiler down, no orphans.
printf 'q' > /tmp/f8090
# 2. Wait for teardown: port free AND no stray compilers.
for i in $(seq 1 10); do curl -sf -o /dev/null --max-time 1 http://localhost:8090/ || break; sleep 1; done
pgrep -f "web-server.*8090" | grep -v "$(pgrep -f 'sleep 1000')" >/dev/null && echo "still draining…"
# 3. Start fresh — KEEP THE CACHE WARM (never `flutter clean` for code changes).
nohup sh -c 'flutter run -d web-server --web-port=8090 --web-hostname=0.0.0.0 < /tmp/f8090 > /tmp/flutter_run_8090.log 2>&1' &
# 4. Wait for the "Flutter run key commands" banner (≈10–20s warm), then reload the browser.
```

A warm incremental build is ~10–20s. If it takes minutes, a zombie compiler is competing or `.dart_tool` went cold — see Recovery.

### After a restart: reload via one fresh tab

Reflecting the new build in the **external** Chrome is its own trap. A hard reload of the existing tab races the dev-server boot (you get the old bundle or a blank canvas), and a CDP screenshot against a mid-boot tab can wedge the connection. The reliable move is to open a **fresh** MCP tab on `http://localhost:8090/` after the banner appears — a new tab always pulls the new bundle.

Fresh tabs pile up fast, so **close the prior tab(s)** — keep exactly one working tab. List with `tabs_context_mcp`, open with `tabs_create_mcp`, then `navigate` the new tab, and only **after** that `tabs_close_mcp` the old ids. Order matters: do NOT close the old tab in the same `browser_batch` *before* the navigate — closing it drops the group's active-tab reference and the next `navigate` fails with "not in the same group". Close as a separate step after the fresh tab is driving. (Closing the group's last tab removes the group; that's fine — the next `tabs_context_mcp {createIfEmpty:true}` starts a fresh one.)

### Never do

- **Never `kill -9` the `flutter run` pid** to stop it — orphans the compiler. Use `q` via the fifo. If `q` won't take (wedged), kill the whole **process group**, not the pid: `kill -- -$(ps -o pgid= -p <pid> | tr -d ' ')`.
- **Never send `R`** in the external-Chrome setup — on a stale DWDS connection its timeout kills the server. Prefer a clean restart over `R` entirely. (`r` on a stale connection just fails harmlessly, but it still didn't apply your change — clean restart.)
- **Never `flutter clean`** just to pick up a code change — it forces a cold build (minutes).

## The fifo control channel

The dev server reads stdin from a FIFO so we can send it `r`/`q` from other shells:

```bash
[ -p /tmp/f8090 ] || mkfifo /tmp/f8090
# Keep ONE writer holding the fifo open, or flutter's stdin hits EOF and it quits
# right after serving (you'll see the banner, then nothing listening on 8090). Two rules:
#   • open it READ-WRITE (`<>`), not write-only — a RW holder never EOFs and never blocks.
#   • reuse the existing holder via a pidfile. Do NOT guard on `pgrep -f sleep` (stale
#     holders from old sessions make that match and skip creation), and do NOT spawn a
#     fresh holder every launch (they pile up as orphaned `sleep` processes).
HPF=/tmp/f8090.holder
if ! { [ -f "$HPF" ] && kill -0 "$(cat "$HPF" 2>/dev/null)" 2>/dev/null; }; then
  ( exec 3<>/tmp/f8090; exec sleep 2147483647 ) & echo $! > "$HPF"
fi
# then launch flutter with `< /tmp/f8090`
```

Send commands with `printf 'r' > /tmp/f8090` (hot reload) or `printf 'q' > /tmp/f8090` (quit). One holder + one `flutter run` only — the pidfile guard above keeps it to one. Orphaned `sleep 100000000` holders from the old write-only pattern are harmless; clear them with `pkill -f 'sleep 100000000'` while no client is running.

## Recovery from a zombie pile / wedged build

```bash
# See every flutter/dart compiler tied to the client (ignore the IDE language-server):
ps -eo pid,ppid,etime,command | grep -iE "web-server|frontend_server|dartaot" | grep -v grep
# Kill each real flutter-run tree by process GROUP (not -9 on the pid):
for pid in $(pgrep -f "web-server.*8090"); do kill -- -$(ps -o pgid= -p "$pid" | tr -d ' ') 2>/dev/null; done
# Confirm 8090 free and no stray compilers, THEN start one clean run.
```

There should be exactly **one** real `flutter run` (a `dartvm … flutter_tools` process) plus its single `sh -c` wrapper. More than one ⇒ kill the extras before starting.

## Env / synapse URL (compile-time — needs a rebuild, not a reload)

The web app fetches its config from `GET /.env` at the dev-server root (served from the repo-root `client/.env`; there is no `assets/.env` since #6975). `.env` changes are compile-time — a hot reload won't pick them up; do a clean restart.

Verify the client is pointed at the **local** stack (not staging) at any time:

```bash
curl -s http://localhost:8090/.env | grep -E "SYNAPSE_URL|HOME_SERVER|CHOREO_API"
# Expect: SYNAPSE_URL=http://localhost:8008 · HOME_SERVER=local.pangea.chat · CHOREO_API=http://localhost:8002
# (CMS_API stays https://api.staging.pangea.chat by design — local CMS has no course content.)
```

`local-dev/pangea env` (the control plane) regenerates these to localhost via `lib/gen-env.sh`; after running it, rebuild Flutter (clean restart) so the new `.env` is served.

### Switching environments (local ↔ staging)

Run the local client against **staging** backends — a fast way to smoke-test a build against real staging data + the staging bot without bringing up the full local stack — by flipping the routing keys in `client/.env` and clean-restarting. Back up first (`.env` is gitignored, so there's no git safety net):

```bash
cp client/.env /tmp/client.env.bak     # restore with: cp /tmp/client.env.bak client/.env
```

These routing keys differ (`CHOREO_API_KEY` is identical in both). **`CMS_API` must match the `SYNAPSE_URL` environment**: the client sends the user's Matrix access token as the CMS bearer, and the CMS validates it against *its own* homeserver — so a mismatched pair (a local `@learner` token against staging CMS, or vice-versa) returns **403** and course/activity content silently fails to load. `CMS_API` is the **host root** — the client appends `/cms/api/...` itself (`PayloadClient.basePath = "/cms/api"`), so do *not* include `/cms` (that yields a `/cms/cms` double path). The local value below needs the **full local stack** (a seeded local CMS, via the `pangea-local-setup` skill); the older local-Synapse-only setup left `CMS_API` at staging and accepted that authed course content does not load.

| Key | Local stack | Staging |
|---|---|---|
| `SYNAPSE_URL` | `http://localhost:8008` | `matrix.staging.pangea.chat` |
| `CHOREO_API`  | `http://localhost:8002` | `https://api.staging.pangea.chat` |
| `CMS_API`     | `http://localhost:13134` *(host root — the client adds `/cms/api`; needs the full local stack)* | `https://api.staging.pangea.chat` |
| `HOME_SERVER` | `local.pangea.chat` | `staging.pangea.chat` *(or omit — it derives from `SYNAPSE_URL`: scheme stripped, leading `matrix.` dropped)* |

Source of truth for the staging values is the deployed client itself: `curl -s https://app.staging.pangea.chat/.env`. After editing, clean-restart and open a **fresh tab** — the dev server caches `/.env` per process, so a reload alone won't switch. Changing the homeserver invalidates the current session, so the app drops to the onboarding/login screen — sign in with the matching account (see Login). **Never point a local build at production.**

### Driving the app by semantics (Chrome extension)

The app renders to `<canvas>`, so the Chrome extension can only operate it by role+name once Flutter's accessibility semantics tree is on — otherwise it falls back to screenshots and positional clicks. Add `ENABLE_SEMANTICS=true` to `client/.env` and clean-restart to force the tree on from startup. Off by default locally (semantics has a perf cost). **Staging** deploys force it on (`main_deploy.yaml` stamps `ENABLE_SEMANTICS=true` into the served `/.env`), so `app.staging.pangea.chat` is driveable by role+name too; **production** leaves it off (on-demand per assistive-tech user). See [`playwright-testing.instructions.md`](../../instructions/playwright-testing.instructions.md) for the full contract.

## Login

- **Local** (`local.pangea.chat`): `@learner` / `learnerpass`.
- **Staging** (`staging.pangea.chat`): the shared `staging_automated_tests` account — credentials in `client/.env` (`TEST_MATRIX_USERNAME` / `TEST_MATRIX_PASSWORD`) or AWS Secrets Manager. See [matrix-auth.instructions.md](../../instructions/matrix-auth.instructions.md).

**Skip the canvas login form: `?devlogin=1`.** The login form is canvas-rendered, so typing into it is the slowest part of a QA loop. In a debug build, open `http://localhost:8090/?devlogin=1` (the param also works inside a hash route, `…/#/world?devlogin=1`) to sign straight into the test account using the `.env` `TEST_MATRIX_*` creds — no typing. It is **opt-in per load** (a plain `localhost:8090` shows the real login flow, so that stays testable), uses the SDK's own login (always-valid session, unlike a stale `storageState`), and refuses production. No-op if already logged in — log out first to switch accounts. See [matrix-auth.instructions.md](../../instructions/matrix-auth.instructions.md).
