#!/bin/bash
# Runs the call route suite ONE ROUTE AT A TIME and writes a results table.
#
#   cd client
#   CALL_WORK_DIR=... ROUTES_OUT=... ROUTES_VARIANT=main test/e2e/routes/run_all.sh [route ...]
#
# Before each route: every Chrome left on a suite profile is killed, so no
# participant or membership from the previous route is still alive; the route
# itself then waits out any server-side membership that has not expired yet and
# sets + confirms its own subscriptions. Evidence for each route lands in
# $ROUTES_OUT/$ROUTES_VARIANT/<route>/ (CALL_SHOT_DIR), and the table in
# $ROUTES_OUT/$ROUTES_VARIANT/results.md.
#
# Preconditions (README.md in this folder): the local stack, this worktree's
# web build served at APP_URL, choreo with CHOREO_REQUIRE_SUBSCRIPTION=true,
# setup_local.js and make_fixtures.sh already run.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLIENT="$(cd "$HERE/../../.." && pwd)"
: "${CALL_WORK_DIR:?set CALL_WORK_DIR (profiles, fixtures, rooms)}"
OUT="${ROUTES_OUT:-$CALL_WORK_DIR/routes-out}/${ROUTES_VARIANT:-run}"
mkdir -p "$OUT"
ALL=(r01_voice_both_good r02_voice_one_throttled r03_video_both_good r04_voice_both_dropend_kill
     r05a_voice_both_switch75 r05b_voice_both_switch150 r06_voice_one_good r07_voice_decline_busy
     r08_voice_missed r09_video_both_second_device r10_video_one_dropmid r11_voice_neither
     r12_video_neither r13_voice_both_noisy r14_voice_es_l1l2 r15_voice_fr_l1l2)
ROUTES=("${@:-${ALL[@]}}")
# One result per route per invocation: a repeated name would overwrite the first.
if [ "$(printf '%s\n' "${ROUTES[@]}" | sort | uniq -d | head -1)" != "" ]; then echo "a route is named twice"; exit 2; fi

clean_browsers() {
  pkill -9 -f "user-data-dir=$CALL_WORK_DIR" 2>/dev/null || true
  sleep 3
  find "$CALL_WORK_DIR" -maxdepth 2 -name 'Singleton*' -delete 2>/dev/null || true
}

RAN=()
# ROUTES_TABLE_ONLY=1 rebuilds the table for the named routes from their
# evidence folders without running anything.
[ -n "${ROUTES_TABLE_ONLY:-}" ] && RAN=("${ROUTES[@]}") && ROUTES=()
for r in ${ROUTES[@]+"${ROUTES[@]}"}; do
  RAN+=("$r")
  if [ ! -f "$HERE/$r.js" ]; then
    echo "no such route: $r"; mkdir -p "$OUT/$r"
    echo "{\"route\":\"$r\",\"pass\":false,\"failing\":[\"no such route file\"]}" > "$OUT/$r/result.json"; continue
  fi
  clean_browsers
  export CALL_SHOT_DIR="$OUT/$r"
  rm -rf "$CALL_SHOT_DIR"; mkdir -p "$CALL_SHOT_DIR"
  echo "=== $r ($(date '+%H:%M:%S'))"
  ( cd "$CLIENT" && timeout 1500 node "test/e2e/routes/$r.js" ) > "$CALL_SHOT_DIR/run.log" 2>&1
  code=$?
  echo "$code" > "$CALL_SHOT_DIR/exit_code"
  echo "    exit $code -> $CALL_SHOT_DIR/run.log"
  [ -f "$CALL_SHOT_DIR/result.json" ] || echo "{\"route\":\"$r\",\"pass\":false,\"failing\":[\"route exited $code before writing a result\"]}" > "$CALL_SHOT_DIR/result.json"
  clean_browsers
done

node -e '
const fs = require("fs"), path = require("path");
const out = process.argv[1];
// Only the routes THIS invocation ran; a result from an earlier run is never reported.
const rows = process.argv.slice(2);
let bad = 0;
let md = "| route | result | failing / unproven assertion(s) | evidence |\n|---|---|---|---|\n";
for (const d of rows) {
  const r = JSON.parse(fs.readFileSync(path.join(out, d, "result.json"), "utf8"));
  const code = fs.existsSync(path.join(out, d, "exit_code")) ? fs.readFileSync(path.join(out, d, "exit_code"), "utf8").trim() : "not run";
  // PASS needs BOTH the route saying so and the process exiting 0 (a timeout
  // after a result was written is not a pass).
  if (code !== "0") {
    // Exit 1 is the route reporting its own FAIL/SKIP; anything else (a
    // timeout is 124) or a 1 beside a "pass" is the process failing.
    if (r.pass || code !== "1") (r.failing = r.failing || []).push(`process exit ${code}`);
    r.pass = false;
  }
  if (!r.pass) bad++;
  const fails = (r.failing || []).map((x) => x.replace(/\|/g, "/").slice(0, 160));
  const skips = (r.skipped || []).map((x) => `SKIP ${x.name}: ${x.why}`.replace(/\|/g, "/").slice(0, 160));
  const status = r.pass ? "PASS" : (fails.length ? "FAIL" : "UNPROVEN");
  md += `| ${d} | ${status} | ${[...fails, ...skips].join("<br>") || "-"} | ${path.join(out, d)} |\n`;
}
fs.writeFileSync(path.join(out, "results.md"), md);
console.log(md);
process.exit(bad ? 1 : 0);
' "$OUT" "${RAN[@]}"
