#!/usr/bin/env bash
# Format lib/ and test/ with the Flutter version pinned in .fvmrc, so local output
# matches the CI `code_tests` format gate. System `dart format` uses whatever Flutter is
# on your PATH and formats Dart differently, so it can report "0 changed" on code that CI
# then rejects. See CONTRIBUTING.md#flutter-version-fvm.
#
#   ./scripts/format.sh          format lib/ and test/ in place
#   ./scripts/format.sh --check  verify only; non-zero exit if anything would change (CI parity)
#
# Import sorting is a separate CI check; run `fvm dart run import_sorter:main --no-comments`
# for that (it resolves packages, so it can touch pubspec.lock).
#
# Locates fvm even when ~/.pub-cache/bin isn't on PATH — the common reason editor and
# Claude Code sessions "can't find fvm" despite it being installed.
set -euo pipefail
cd "$(dirname "$0")/.."

fvm_bin="$(command -v fvm || true)"
if [ -z "$fvm_bin" ]; then
  for cand in "$HOME/.pub-cache/bin/fvm" /opt/homebrew/bin/fvm /usr/local/bin/fvm; do
    [ -x "$cand" ] && fvm_bin="$cand" && break
  done
fi
if [ -z "$fvm_bin" ]; then
  echo "error: fvm not found. Install it — 'brew install fvm', or 'dart pub global activate fvm'" >&2
  echo "       then add ~/.pub-cache/bin to your PATH. See CONTRIBUTING.md#flutter-version-fvm." >&2
  exit 1
fi

if [ "${1:-}" = "--check" ]; then
  exec "$fvm_bin" dart format lib/ test/ --set-exit-if-changed
else
  exec "$fvm_bin" dart format lib/ test/
fi
