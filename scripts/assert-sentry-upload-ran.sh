#!/bin/sh -eu

# Fail the deploy when sentry_dart_plugin degraded but still exited 0.
#
# The plugin has several non-fatal failure paths that all end at
# `_setPreInstalledCli()`, which points cliPath at a bare `sentry-cli` and hopes
# it is on PATH (configuration.dart): an unsupported host platform, a failed CLI
# download, and a failed `chmod +x`. Nothing in our workflows installs
# sentry-cli, so reaching that fallback means the upload cannot happen. The
# process spawn then throws, and `_executeAndLog` catches the exception, logs
# it, and leaves exitCode null -- so `Log.processExitCode` never runs, no
# ExitError is thrown, and the plugin returns 0 having uploaded nothing (#8656).
#
# Every one of those paths prints to stdout (Log._write is stdout.writeln, for
# Log.error as well as Log.info), so the plugin's own output is the signal.
# These strings are emitted ONLY on failure paths, so a match cannot be a
# healthy run -- the reverse of the artifact-API probe reverted in #8667, which
# could not tell an empty answer from a wrong question.
#
# Coupled to the log strings of the pinned plugin version. pubspec.yaml pins it
# exactly for that reason; re-check these patterns when that pin moves.
#
# Usage: assert-sentry-upload-ran.sh <logfile>

log="${1:?usage: assert-sentry-upload-ran.sh <logfile>}"
[ -f "$log" ] || { echo "assert-sentry-upload-ran: no log at $log" >&2; exit 1; }

# Matched against ANSI-coloured output: Log.error wraps the whole message, so
# the text stays contiguous and a plain match still works.
patterns='Trying to fallback to preinstalled Sentry CLI
Failed to download Sentry CLI
Failed to make downloaded Sentry CLI executable
Host platform not supported
Failed to upload source maps
Failed to upload symbols'

hit=0
echo "$patterns" | while IFS= read -r p; do
  [ -n "$p" ] || continue
  if grep -qF "$p" "$log"; then
    echo "::error::sentry_dart_plugin degraded but exited 0 -- matched: $p"
    exit 1
  fi
done || hit=1

[ "$hit" -eq 0 ] || {
  echo "assert-sentry-upload-ran: FAILED -- source maps were not uploaded." >&2
  echo "  The plugin logged a degradation and still exited 0. See #8656." >&2
  exit 1
}

echo "assert-sentry-upload-ran: OK -- no degradation signatures in plugin output"
