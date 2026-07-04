#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit) nudge — client only. When client/.env is about to be
# edited, remind that the dev server caches it once at process startup (neither hot reload nor
# a browser reload picks up the change), plus the adjacent never-point-at-production and
# CMS_API/SYNAPSE_URL-pairing warnings from the same section of run-flutter-web-local. Fires
# every time — an .env edit is rare enough that repetition isn't a real cost, and each edit is
# an independent moment to get this right. Advisory only; never blocks (always exit 0).
#
# Message wording lives in ../hooks/on-flutter-env-edit.md (harness-sync.instructions.md
# § Hook message files, repo-specific hooks).
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"
payload=$(cat)
fp=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
[ -z "$fp" ] && exit 0
[ "$(basename "$fp")" = ".env" ] || exit 0

line=""; out=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '<!--'*) continue ;; esac
  [ -z "$out" ] && [ -z "$line" ] && continue
  out="${out:+$out }$line"
done < "$HOOKS_DIR/on-flutter-env-edit.md"

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}' "$(printf '%s' "$out" | jq -Rs .)"
exit 0
