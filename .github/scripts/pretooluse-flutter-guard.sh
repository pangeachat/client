#!/usr/bin/env bash
# PreToolUse(Bash) safety checks — client only, for the Flutter dev-server workflow. Distinct
# from pretooluse-flutter-skill.sh (which points to the skill once per session, on `flutter run`):
# these are per-command nudges for specific traps the skill documents, since each occurrence
# is an independent moment where the same mistake can recur. Advisory only; never blocks.
#
# Message wording lives in ../hooks/on-flutter-*.md (harness-sync.instructions.md § Hook
# message files, repo-specific hooks).
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"
payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

msg=""
add() { msg="${msg:+$msg  ||  }$1"; }
m()   { printf '%s' "$cmd" | grep -qE "$1"; }

# Read an on-*.md single-message file: drop comment lines and leading blank lines, join the rest
# into one line (messages are one paragraph; the source file may wrap it for readability).
text() {
  local file="$HOOKS_DIR/$1" line out=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '<!--'*) continue ;; esac
    [ -z "$out" ] && [ -z "$line" ] && continue
    out="${out:+$out }$line"
  done < "$file"
  printf '%s' "$out"
}

# --- kill/pkill guard: fires every time, no session suppression. This is a recurring safety
# moment (a wrong kill orphans compilers each time), not a one-time orientation fact. ---
if m '\b(kill|pkill)\b' && m '8090|flutter|web-server|frontend_server|dartaot'; then
  add "$(text on-flutter-kill.md)"
fi

# --- bare-toolchain guard: once per session (a habit correction, likely to stick once made). ---
if m '\b(flutter|dart)\s+(run|build|test|analyze|pub|clean|doctor|create|devices|channel|upgrade|format|fix|--version)\b' && ! m '\bfvm\b'; then
  session=$(printf '%s' "$payload" | jq -r '.session_id // "nosess"' 2>/dev/null)
  flag="${TMPDIR:-/tmp}/flutter-bare-toolchain-${session}.flag"
  if [ ! -f "$flag" ]; then
    : > "$flag"
    add "$(text on-flutter-bare-toolchain.md)"
  fi
fi

# --- hot-restart (capital R) guard: fires every time, no suppression. Sending R even once can
# kill the dev server on a stale DWDS connection — a recurring risk, not a one-time fact. ---
if m "['\"]R['\"]" && m '/tmp/f8090'; then
  add "$(text on-flutter-hot-restart.md)"
fi

# --- flutter clean guard: fires every time. Cheap to warn every time since the command itself
# is rare, and each occurrence is an independent "is this really necessary" moment. ---
if m '\bflutter\s+clean\b'; then
  add "$(text on-flutter-clean.md)"
fi

[ -n "$msg" ] && printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}' "$(printf '%s' "$msg" | jq -Rs .)"
exit 0
