#!/usr/bin/env bash
#
# ONBOARDING / RESET ONLY — not a maintenance step. This OVERWRITES every
# managed env var in your .env with whatever AWS Secrets Manager currently
# holds. If your existing .env has working values you want to keep, do NOT
# re-run this — it will clobber them silently. Use `aws secretsmanager
# get-secret-value` for one-off lookups instead.
#
# Pulls the shared `staging_automated_tests` Matrix credentials from AWS
# Secrets Manager (/staging/test-user/matrix-credentials) into your local
# client/.env, for Playwright + manual auth flows. Same source CI's e2e
# workflow uses.
#
# Usage:
#   AWS_PROFILE=PangeaChat-Dev ./scripts/sync-dev-secrets.sh [--dry-run] [--out PATH]
#
# Behavior mirrors choreo/cms/pangea-bot:
# - Reads SECRET_MAP below (env-var → secret-name#json-key)
# - OVERWRITES managed env vars (anything in SECRET_MAP) with the fetched values
# - Preserves env vars NOT in SECRET_MAP (your personal additions stay)
#
# Run `aws sso login --profile PangeaChat-Dev` first if AWS_PROFILE is unset
# or the session has expired.

set -euo pipefail

OUT=".env"
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${AWS_PROFILE:-}" ]]; then
  echo "error: AWS_PROFILE must be set (e.g. AWS_PROFILE=PangeaChat-Dev)" >&2
  exit 1
fi

# env-var → AWS Secrets Manager secret name.
# JSON-shaped secrets use ENV_VAR=secret-name#json-key form.
SECRET_MAP=(
  "TEST_MATRIX_USERNAME=/staging/test-user/matrix-credentials#username"
  "TEST_MATRIX_PASSWORD=/staging/test-user/matrix-credentials#password"
  "GOOGLE_ANALYTICS_FIREBASE_OPTIONS_BASE64=/staging/firebase/google-analytics#web"
  "GOOGLE_SERVICES_JSON=/staging/firebase/google-analytics#android"
  "GOOGLE_SERVICES_PLIST=/staging/firebase/google-analytics#ios"
)

fetch_secret() {
  local secret_name="$1"
  local json_key="${2:-}"
  local raw
  raw=$(aws secretsmanager get-secret-value --secret-id "$secret_name" --query SecretString --output text 2>/dev/null) || return 1
  if [[ -n "$json_key" ]]; then
    echo "$raw" | python3 -c "import sys, json; print(json.load(sys.stdin).get('$json_key', ''))"
  else
    echo "$raw"
  fi
}

# Track managed keys as space-delimited string (bash 3-compatible — no `declare -A`).
MANAGED_VARS=""
for entry in "${SECRET_MAP[@]}"; do
  MANAGED_VARS="$MANAGED_VARS ${entry%%=*}"
done

is_managed() {
  case " $MANAGED_VARS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

if [[ -f "$OUT" ]]; then
  while IFS= read -r line; do
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
      printf '%s\n' "$line" >> "$TMP_FILE"
      continue
    fi
    key="${line%%=*}"
    if ! is_managed "$key"; then
      printf '%s\n' "$line" >> "$TMP_FILE"
    fi
  done < "$OUT"
  printf '\n' >> "$TMP_FILE"
fi

printf '# --- Synced by sync-dev-secrets.sh on %s ---\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$TMP_FILE"

for entry in "${SECRET_MAP[@]}"; do
  env_var="${entry%%=*}"
  rest="${entry#*=}"
  secret_name="${rest%%#*}"
  json_key=""
  [[ "$rest" == *"#"* ]] && json_key="${rest#*#}"

  printf '  fetching %s ← %s' "$env_var" "$secret_name"
  [[ -n "$json_key" ]] && printf '#%s' "$json_key"
  printf '... '

  if value=$(fetch_secret "$secret_name" "$json_key"); then
    printf '%s="%s"\n' "$env_var" "$value" >> "$TMP_FILE"
    printf 'ok\n'
  else
    printf 'FAILED — does the secret exist? skipping.\n'
    printf '# %s= (sync failed: secret %s not found or access denied)\n' "$env_var" "$secret_name" >> "$TMP_FILE"
  fi
done

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  echo "DRY RUN — would write to $OUT:"
  echo "────────────────────────────────────────"
  cat "$TMP_FILE"
else
  mv "$TMP_FILE" "$OUT"
  trap - EXIT
  echo
  echo "wrote $OUT"
fi
