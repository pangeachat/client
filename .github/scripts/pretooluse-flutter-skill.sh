#!/usr/bin/env bash
# PreToolUse(Bash) nudge — client only. When the agent is about to spin up the Flutter web
# client (`flutter run`), point to the run-flutter-web-local skill if it likely isn't already
# in context. The skill is the clean-restart procedure that avoids the recurring local hang;
# this only points to it (the procedure lives in the skill, not here). Fires once per session.
# Advisory only; never blocks (always exit 0).
payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
printf '%s' "$cmd" | grep -qE '\bflutter run\b' || exit 0

session=$(printf '%s' "$payload" | jq -r '.session_id // "nosess"' 2>/dev/null)
flag="${TMPDIR:-/tmp}/flutter-skill-${session}.flag"
[ -f "$flag" ] && exit 0   # already pointed this session — assume it's in context now
: > "$flag"

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}' \
  "Before spinning up the Flutter client: if the run-flutter-web-local skill isn't already in context, read .github/skills/run-flutter-web-local/SKILL.md first. It is the clean-restart procedure that avoids the recurring local hang — stale-DWDS r/R timeouts that kill port 8090, and orphaned compilers from kill -9. Use it for the start AND every restart."
exit 0
