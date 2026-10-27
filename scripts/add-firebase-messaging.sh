#!/usr/bin/env bash
set -euo pipefail

# CI installs the pinned Flutter via subosito/flutter-action (integrate.yaml checks it
# against .fvmrc) and has no fvm. Locally, bare `flutter` is whatever is on PATH, so
# require fvm there.
if [ "${CI:-}" = "true" ]; then
  flutter_cmd=(flutter)
else
  source "$(dirname "$0")/lib/fvm.sh"
  flutter_cmd=("$fvm_bin" flutter)
fi

"${flutter_cmd[@]}" pub add fcm_shared_isolate
"${flutter_cmd[@]}" pub get

if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' 's,//<GOOGLE_SERVICES>,,g' lib/utils/background_push.dart
  sed -i '' -e 's,^/\*,,' -e 's,\*/$,,' android/app/src/main/kotlin/com/talktolearn/chat/FcmPushService.kt
else
  sed -i 's,//<GOOGLE_SERVICES>,,g' lib/utils/background_push.dart
  sed -i -e 's,^/\*,,' -e 's,\*/$,,' android/app/src/main/kotlin/com/talktolearn/chat/FcmPushService.kt
fi
