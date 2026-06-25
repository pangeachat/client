#!/bin/sh -ve

# Retry the web build: flutter_rust_bridge_codegen downloads binaryen from
# GitHub releases, which intermittently flakes (transient network / rate
# limits) and fails the build even though the asset is available. Retrying the
# command re-attempts the download.
retry() {
  attempt=1
  while true; do
    "$@" && return 0
    status=$?
    if [ "$attempt" -ge 3 ]; then
      echo "retry: '$*' failed after $attempt attempts (exit $status)" >&2
      return "$status"
    fi
    echo "retry: '$*' failed (attempt $attempt/3, exit $status), retrying in 15s..." >&2
    attempt=$((attempt + 1))
    sleep 15
  done
}

version=$(yq ".dependencies.flutter_vodozemac" < pubspec.yaml)
version=$(expr "$version" : '\^*\(.*\)')
git clone https://github.com/famedly/dart-vodozemac.git -b ${version} .vodozemac
cd .vodozemac
cargo install flutter_rust_bridge_codegen
retry flutter_rust_bridge_codegen build-web --dart-root dart --rust-root $(readlink -f rust) --release
cd ..
rm -f ./assets/vodozemac/vodozemac_bindings_dart*
mv .vodozemac/dart/web/pkg/vodozemac_bindings_dart* ./assets/vodozemac/
rm -rf .vodozemac

flutter pub get
dart compile js ./web/native_executor.dart -o ./web/native_executor.js -m
