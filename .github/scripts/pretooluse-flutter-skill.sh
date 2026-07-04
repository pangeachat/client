#!/usr/bin/env bash
# PreToolUse(Bash) nudge — client only. When the agent is about to spin up the Flutter web
# client (`flutter run`), point to the run-flutter-web-local skill if it likely isn't already
# in context. The skill is the clean-restart procedure that avoids the recurring local hang;
# this only points to it (the procedure lives in the skill, not here). Fires once per session.
# Advisory only; never blocks (always exit 0).
#
# Message wording lives in ../hooks/on-flutter-run.md (harness-sync.instructions.md § Hook
# message files, repo-specific hooks) — this script only matches the trigger and reads the file.
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"
payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
printf '%s' "$cmd" | grep -qE '\bflutter run\b' || exit 0

session=$(printf '%s' "$payload" | jq -r '.session_id // "nosess"' 2>/dev/null)
flag="${TMPDIR:-/tmp}/flutter-skill-${session}.flag"
[ -f "$flag" ] && exit 0   # already pointed this session — assume it's in context now
: > "$flag"

# Read on-flutter-run.md: drop comment lines and leading blank lines, join the rest into one line.
line=""; out=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '<!--'*) continue ;; esac
  [ -z "$out" ] && [ -z "$line" ] && continue
  out="${out:+$out }$line"
done < "$HOOKS_DIR/on-flutter-run.md"

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}' "$(printf '%s' "$out" | jq -Rs .)"
exit 0
