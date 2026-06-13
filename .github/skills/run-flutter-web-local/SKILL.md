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

## The three traps (diagnosed empirically)

1. **`r` (hot reload) cannot apply structural changes.** Adding an enum value (e.g. a new `AppSection`), changing the GoRouter route tree, adding a new top-level file, or touching a `const`/generic is NOT hot-reloadable. Sending `r` after such a change silently no-ops — the app keeps running the OLD code and looks "stuck" or wrong. Most of our "it hung" incidents are really "`r` couldn't apply an enum/route change."
2. **`R` (hot restart) over `-d web-server` is a landmine with an external browser.** `R` waits for the browser's Dart debug (DWDS) websocket to ack the restart. With an external Chrome whose connection has gone stale (it was connected to a previous/killed `flutter run`, or the tab slept), `R` gets `0/1 responses`, times out after **15s, and the timeout KILLS the `flutter run` process** — leaving port 8090 dead. This is the classic "I pressed restart and now nothing loads."
3. **`kill -9` of the `flutter run` parent orphans its compiler.** `flutter run` spawns a `frontend_server`/`dartaot` child. `kill -9 <parent>` (or `kill` followed too quickly by `-9`) leaves that child running. Orphaned compilers pile up, hold the build lock under `.dart_tool/`, and starve CPU — so the NEXT `flutter run` hangs or goes cold. This is the "lots of background dart processes" pile.

## The procedure

### Reflecting a code change in the browser

- **Non-structural change** (widget body, style, string, method body): `printf 'r' > /tmp/f8090` then reload the browser tab. ~5–10s.
- **Structural change** (enum value, route tree, new file, `const`, top-level decl) OR anything `r` didn't pick up: **do a clean restart** (below). Do NOT reach for `R` in this setup — see trap #2.

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

### Never do

- **Never `kill -9` the `flutter run` pid** to stop it — orphans the compiler. Use `q` via the fifo. If `q` won't take (wedged), kill the whole **process group**, not the pid: `kill -- -$(ps -o pgid= -p <pid> | tr -d ' ')`.
- **Never send `R`** to a `flutter run` whose browser tab isn't freshly connected — the 15s timeout kills the server. In the external-Chrome setup, prefer a clean restart over `R` entirely.
- **Never `flutter clean`** just to pick up a code change — it forces a cold build (minutes).

## The fifo control channel

The dev server reads stdin from a FIFO so we can send it `r`/`q` from other shells:

```bash
[ -p /tmp/f8090 ] || mkfifo /tmp/f8090
( sleep 100000000 > /tmp/f8090 & )   # holder keeps the FIFO open for writing
# then launch flutter with `< /tmp/f8090`
```

Send commands with `printf 'r' > /tmp/f8090` (hot reload) or `printf 'q' > /tmp/f8090` (quit). One holder + one `flutter run` only.

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

## Login

`@learner` / `learnerpass` against the local Synapse (`local.pangea.chat`).
