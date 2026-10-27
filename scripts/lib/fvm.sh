# Sourced, not executed. Sets fvm_bin to the fvm executable, or exits 1 with install help.
#
# Locates fvm even when ~/.pub-cache/bin isn't on PATH — the common reason editor and
# Claude Code sessions "can't find fvm" despite it being installed.

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
