#!/usr/bin/env bash
# Switch client/.env between environment profiles.
#
# .env is a generated artifact: the canonical per-environment files are
# .env.<profile> (gitignored, e.g. .env.local / .env.staging), each carrying
# the routing keys AND the test credentials that exist on that environment's
# homeserver — so the endpoint test suites and ?devlogin=1 always target the
# active environment with credentials that work there. Never edit .env in
# place; edit the profile and re-run this script.
#
# Usage: scripts/use-env.sh <profile>     e.g. scripts/use-env.sh local
set -euo pipefail
cd "$(dirname "$0")/.."

profile="${1:-}"
if [ -z "$profile" ] || [ ! -f ".env.$profile" ]; then
  echo "usage: scripts/use-env.sh <profile>   (needs client/.env.<profile>)"
  echo "available profiles:"
  ls -1 .env.* 2>/dev/null | grep -v example | sed 's/^\.env\./  /' || echo "  (none — create .env.local / .env.staging first)"
  exit 1
fi

cp ".env.$profile" .env
echo ".env is now the '$profile' profile."
echo "Clean-restart the dev server — it caches /.env per process (see the run-flutter-web-local skill)."
