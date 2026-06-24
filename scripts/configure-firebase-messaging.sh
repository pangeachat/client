#!/usr/bin/env bash
set -euo pipefail

decode_base64_file() {
  local env_var="$1"
  local destination="$2"
  local value="${!env_var:-}"

  if [[ -z "$value" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$destination")"
  local temp_file
  temp_file="$(mktemp "${destination}.XXXXXX")"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    if printf '%s' "$value" | base64 -D > "$temp_file"; then
      mv "$temp_file" "$destination"
      echo "Wrote $destination from $env_var"
      return 0
    fi
  else
    if printf '%s' "$value" | base64 --decode > "$temp_file"; then
      mv "$temp_file" "$destination"
      echo "Wrote $destination from $env_var"
      return 0
    fi
  fi

  rm -f "$temp_file"
  echo "Unable to decode $env_var as base64" >&2
  return 1
}

decode_base64_file GOOGLE_SERVICES_JSON android/app/google-services.json
decode_base64_file GOOGLE_SERVICES_PLIST ios/Runner/GoogleService-Info.plist

./scripts/add-firebase-messaging.sh
