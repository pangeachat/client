#!/bin/bash
# selftest.sh -- synthetic self-test for merge_call_audio.
#
# Generates two tone WAVs with a KNOWN, manifest-encoded start offset, runs
# the tool, and checks:
#   - both outputs get produced
#   - the printed per-half delay matches the known offset
#   - the delay landed on the CORRECT half (via a duration asymmetry that a
#     min/max swap bug would flip -- see comment before Test A)
#   - the --clap-ms fallback path works and is exercised symmetrically
#   - missing timestamps without --clap-ms refuses to guess (never a silent
#     misalignment)
#   - a missing input file and a malformed manifest both fail loudly
#
# Usage: ./selftest.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL="$SCRIPT_DIR/merge_call_audio"

FFMPEG_BIN="$(command -v ffmpeg || true)"
[ -n "$FFMPEG_BIN" ] || FFMPEG_BIN="/opt/homebrew/bin/ffmpeg"
[ -x "$FFMPEG_BIN" ] || { echo "ERROR: ffmpeg not found (needed to generate self-test fixtures)" >&2; exit 2; }
FFPROBE_BIN="$(command -v ffprobe || true)"
[ -n "$FFPROBE_BIN" ] || FFPROBE_BIN="/opt/homebrew/bin/ffprobe"
[ -x "$FFPROBE_BIN" ] || { echo "ERROR: ffprobe not found" >&2; exit 2; }

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/merge_call_audio_selftest.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }

get_field() { # $1=stdout_file $2=label $3=field_name(e.g. delay_ms)
  grep "^HALF label=$2 " "$1" | sed -E "s/.*${3}=([0-9]+).*/\\1/"
}

assert_eq() { # actual expected description
  if [ "$1" = "$2" ]; then pass "$3 (got $1)"; else fail "$3 (expected $2, got $1)"; fi
}

assert_close() { # actual expected tolerance description
  local ok
  ok="$(awk -v a="$1" -v e="$2" -v t="$3" 'BEGIN{d=(a>e)?a-e:e-a; print (d<=t)?"1":"0"}')"
  if [ "$ok" = "1" ]; then
    pass "$4 (actual=$1 expected=$2 tol=$3)"
  else
    fail "$4 (actual=$1 expected=$2 tol=$3)"
  fi
}

assert_exit_nonzero() { # description -- expects the previously-run $STATUS to be nonzero
  if [ "$STATUS" -ne 0 ]; then pass "$1 (exit=$STATUS)"; else fail "$1 (expected nonzero exit, got 0)"; fi
}

assert_stderr_contains() { # needle description
  if grep -qF "$1" "$STDERR_FILE"; then pass "$2"; else fail "$2 (stderr did not contain '$1')"; fi
}

run_tool() { # runs $TOOL "$@", capturing stdout/stderr/status into globals
  STDOUT_FILE="$WORKDIR/stdout.$RANDOM"
  STDERR_FILE="$WORKDIR/stderr.$RANDOM"
  set +e
  "$TOOL" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  STATUS=$?
  set -e
}

# ---- fixtures: two tones, DELIBERATELY different durations so a min/max
# swap bug changes the merged output's total length (see Test A/B below). ----

YOU_WAV="$WORKDIR/you.wav"
FRIEND_WAV="$WORKDIR/friend.wav"
"$FFMPEG_BIN" -y -loglevel error -f lavfi -i "sine=frequency=440:duration=1:sample_rate=48000" -ac 1 -c:a pcm_s16le "$YOU_WAV"
"$FFMPEG_BIN" -y -loglevel error -f lavfi -i "sine=frequency=880:duration=3:sample_rate=48000" -ac 1 -c:a pcm_s16le "$FRIEND_WAV"

duration_of() { "$FFPROBE_BIN" -v error -show_entries format=duration -of default=nk=1:nw=1 "$1"; }
YOU_DUR="$(duration_of "$YOU_WAV")"
FRIEND_DUR="$(duration_of "$FRIEND_WAV")"

# ============================================================================
# Test A -- timestamp method. "friend" is the LATER-starting half by a known
# 300ms (file_start_sfu_ms: you=1,000,200  friend=1,000,500). Correct
# alignment delays "friend" by 300ms and "you" by 0ms, so the merged output
# is dominated by friend's own length plus its delay: 3.0s + 0.3s = 3.3s.
# If a min/max swap bug delayed "you" instead, the output would be
# max(1.0+0.3, 3.0+0) = 3.0s -- a full 300ms shorter, so this duration check
# fails loudly on that class of bug rather than only checking the printed
# number.
# ============================================================================
MANIFEST_A="$WORKDIR/halves_a.json"
cat >"$MANIFEST_A" <<EOF
[
  {"sender":"@you:example.org","label":"you","file":"$YOU_WAV","recording_started_offset_from_device_join_ms":200,"device_joined_at_ms":999500,"sfu_joined_at_ms":1000000},
  {"sender":"@friend:example.org","label":"friend","file":"$FRIEND_WAV","recording_started_offset_from_device_join_ms":500,"device_joined_at_ms":999800,"sfu_joined_at_ms":1000000}
]
EOF
OUT_A="$WORKDIR/out_a"
run_tool --manifest "$MANIFEST_A" --out "$OUT_A"
assert_eq "$STATUS" "0" "Test A: timestamp-method run exits 0"
[ -s "$OUT_A/merged_stereo.wav" ] && pass "Test A: stereo output exists and is non-empty" || fail "Test A: stereo output missing/empty"
[ -s "$OUT_A/merged_mono.wav" ] && pass "Test A: mono output exists and is non-empty" || fail "Test A: mono output missing/empty"
assert_eq "$(get_field "$STDOUT_FILE" you delay_ms)" "0" "Test A: 'you' (earlier start) computed delay"
assert_eq "$(get_field "$STDOUT_FILE" friend delay_ms)" "300" "Test A: 'friend' (later start) computed delay matches known 300ms offset"
if [ -s "$OUT_A/merged_stereo.wav" ] && [ -s "$OUT_A/merged_mono.wav" ]; then
  assert_close "$(duration_of "$OUT_A/merged_stereo.wav")" "3.3" "0.15" "Test A: stereo output duration (catches a min/max swap bug: wrong direction gives 3.0s)"
  assert_close "$(duration_of "$OUT_A/merged_mono.wav")" "3.3" "0.15" "Test A: mono output duration"
fi

# ============================================================================
# Test B -- clap-ms fallback, exercised with the delay landing on the OTHER
# half (you=200ms clap, friend=500ms clap -> max=500 -> delay(you)=300,
# delay(friend)=0) to cross-check the swap-sensitivity isn't an artifact of
# which label happens to be first in the manifest. Correct duration here is
# max(1.0+0.3, 3.0+0)=3.0s; the swapped-bug alternative would be 3.3s.
# ============================================================================
MANIFEST_B="$WORKDIR/halves_b.json"
cat >"$MANIFEST_B" <<EOF
[
  {"sender":"@you:example.org","label":"you","file":"$YOU_WAV"},
  {"sender":"@friend:example.org","label":"friend","file":"$FRIEND_WAV"}
]
EOF

# B1: no --clap-ms and no usable timestamps -> must refuse, never guess.
run_tool --manifest "$MANIFEST_B" --out "$WORKDIR/out_b1"
assert_exit_nonzero "Test B1: missing timestamps + no --clap-ms refuses to align"
assert_stderr_contains "clap-ms" "Test B1: error message points at --clap-ms as the fix"

# B2: with --clap-ms, both directions exercised.
OUT_B2="$WORKDIR/out_b2"
run_tool --manifest "$MANIFEST_B" --out "$OUT_B2" --clap-ms "you=200,friend=500"
assert_eq "$STATUS" "0" "Test B2: clap-ms fallback run exits 0"
assert_eq "$(get_field "$STDOUT_FILE" you delay_ms)" "300" "Test B2: 'you' (earlier clap-derived start) computed delay"
assert_eq "$(get_field "$STDOUT_FILE" friend delay_ms)" "0" "Test B2: 'friend' (later clap-derived start) computed delay"
if [ -s "$OUT_B2/merged_stereo.wav" ]; then
  assert_close "$(duration_of "$OUT_B2/merged_stereo.wav")" "3.0" "0.15" "Test B2: stereo output duration (swap-bug alternative would be 3.3s)"
fi

# ============================================================================
# Test C -- a half's audio file does not exist -> clear non-zero exit naming
# the missing file, never a silent skip.
# ============================================================================
MANIFEST_C="$WORKDIR/halves_c.json"
cat >"$MANIFEST_C" <<EOF
[
  {"sender":"@you:example.org","label":"you","file":"$YOU_WAV","recording_started_offset_from_device_join_ms":0,"device_joined_at_ms":1000000,"sfu_joined_at_ms":1000000},
  {"sender":"@friend:example.org","label":"friend","file":"does_not_exist.wav","recording_started_offset_from_device_join_ms":0,"device_joined_at_ms":1000000,"sfu_joined_at_ms":1000000}
]
EOF
run_tool --manifest "$MANIFEST_C" --out "$WORKDIR/out_c"
assert_exit_nonzero "Test C: missing audio file refuses to run"
assert_stderr_contains "does_not_exist.wav" "Test C: error message names the missing file"

# ============================================================================
# Test D -- malformed manifest JSON -> clear non-zero exit, not a crash/trace.
# ============================================================================
MANIFEST_D="$WORKDIR/halves_d.json"
printf 'this is not json' >"$MANIFEST_D"
run_tool --manifest "$MANIFEST_D" --out "$WORKDIR/out_d"
assert_exit_nonzero "Test D: malformed manifest JSON refuses to run"

# ============================================================================
echo "----"
echo "selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
