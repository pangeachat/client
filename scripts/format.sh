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
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/lib/fvm.sh

if [ "${1:-}" = "--check" ]; then
  exec "$fvm_bin" dart format lib/ test/ --set-exit-if-changed
else
  exec "$fvm_bin" dart format lib/ test/
fi
