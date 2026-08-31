#!/bin/sh -eu

# Assert that the Sentry release we just uploaded to actually has artifacts.
#
# `flutter packages pub run sentry_dart_plugin` exits 0 as soon as the upload is
# handed off -- sentry.properties sets `wait_for_processing=false` -- so a clean
# exit is not evidence that anything landed. Nothing downstream notices either:
# a release with no source maps looks exactly like a healthy one until someone
# opens a minified stack trace in Sentry weeks later (#8656).
#
# Fails only on positive evidence of absence: the API answered, and the release
# has zero artifacts. An API call that does not answer -- network, auth, an
# endpoint shape that changed under us -- is an unanswered question, not a
# failed upload, so it warns and lets the deploy through. A verification step
# that can red-light a release on its own inability to check is worse than the
# gap it closes.
#
# Usage: verify-sentry-artifacts.sh
# Requires: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT, SENTRY_RELEASE

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN not set}"
: "${SENTRY_ORG:?SENTRY_ORG not set}"
: "${SENTRY_PROJECT:?SENTRY_PROJECT not set}"
: "${SENTRY_RELEASE:?SENTRY_RELEASE not set}"

# The release contains `@` and `+`, both of which are path-significant.
encoded_release=$(printf '%s' "$SENTRY_RELEASE" | sed 's/@/%40/g; s/+/%2B/g')
url="https://sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/releases/${encoded_release}/files/?per_page=1"

# Uploads are still processing when the plugin returns, so an empty first
# answer is expected rather than fatal. Poll before believing it.
attempt=1
max_attempts=6
while [ "$attempt" -le "$max_attempts" ]; do
  body_file=$(mktemp)
  status=$(curl -sS -o "$body_file" -w '%{http_code}' \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "$url" 2>/dev/null) || status="000"

  if [ "$status" = "200" ]; then
    # Any element at all means artifacts exist; `[]` means they do not.
    if grep -q '"id"' "$body_file"; then
      echo "verify-sentry-artifacts: OK -- $SENTRY_RELEASE has artifacts"
      rm -f "$body_file"
      exit 0
    fi
    echo "verify-sentry-artifacts: no artifacts yet (attempt $attempt/$max_attempts)"
  else
    echo "verify-sentry-artifacts: HTTP $status from Sentry (attempt $attempt/$max_attempts)"
    head -c 300 "$body_file" || true
    echo
  fi

  last_status="$status"
  rm -f "$body_file"
  attempt=$((attempt + 1))
  [ "$attempt" -le "$max_attempts" ] && sleep 10
done

if [ "${last_status:-000}" != "200" ]; then
  echo "verify-sentry-artifacts: WARNING -- could not reach the Sentry releases API" >&2
  echo "  (last status: ${last_status:-000}). Not failing: an unanswered check is" >&2
  echo "  not evidence of a bad upload. Verify $SENTRY_RELEASE by hand." >&2
  exit 0
fi

echo "verify-sentry-artifacts: FAILED -- $SENTRY_RELEASE has no artifacts" >&2
echo "  sentry_dart_plugin reported success but Sentry has nothing for this" >&2
echo "  release. Web stack traces will stay minified. Check the Update sentry" >&2
echo "  step's log, and that SENTRY_RELEASE/SENTRY_DIST match what the app" >&2
echo "  reports (see #8413)." >&2
exit 1
