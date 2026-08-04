#!/bin/sh -e

# flutter build web, with the self-hosted CanvasKit served from an
# engine-revision-versioned path (canvaskit/<engineRevision>/) instead of the
# default unversioned canvaskit/.
#
# main.dart.js and canvaskit.{js,wasm} are one artifact split across files: a
# bundle from one engine running against CanvasKit from another crashes at the
# first canvas paint (#8084, Sentry CLIENT-CN4 — a cached pre-Flutter-3.41
# shell calling Path.addRect on a CanvasKit that had moved it to PathBuilder).
# Our deploys cache canvaskit/* as immutable for a year, so the unversioned
# path made that skew inevitable across engine bumps. Versioning the path by
# engine revision makes each bundle request exactly the engine it was built
# with, and keeping old revision dirs in the bucket (the s3 sync never
# deletes) lets stale cached shells keep finding theirs.
#
# Usage: ./scripts/build-web-versioned-canvaskit.sh [flutter build web flags...]

ENGINE_REV=$(flutter --version --machine | jq -r .engineRevision)
if [ -z "$ENGINE_REV" ] || [ "$ENGINE_REV" = "null" ]; then
  echo "build-web-versioned-canvaskit: could not resolve engine revision" >&2
  exit 1
fi
echo "build-web-versioned-canvaskit: CanvasKit URL is canvaskit/$ENGINE_REV/"

flutter build web --dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/$ENGINE_REV/ "$@"

mv build/web/canvaskit "build/web/canvaskit-$ENGINE_REV"
mkdir build/web/canvaskit
mv "build/web/canvaskit-$ENGINE_REV" "build/web/canvaskit/$ENGINE_REV"
